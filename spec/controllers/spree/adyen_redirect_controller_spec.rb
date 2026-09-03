require "spec_helper"

# https://docs.adyen.com/display/TD/HPP+payment+response
RSpec.describe Spree::AdyenRedirectController, type: :controller do
  include_context "mock adyen client", success: true

  let(:order) do
    create(
      :order_with_line_items,
      state: "payment",
      store: store
    )
  end

  let!(:store) { create :store }
  let!(:gateway) { create :hpp_gateway }

  before do
    allow(controller).to receive(:check_signature)
  end

  describe "GET confirm" do
    subject(:action) { get :confirm, params: params }

    let(:psp_reference) { "8813824003752247" }
    let(:payment_method) { "amex" }
    let(:merchantReturnData) { "#{order.guest_token}|#{gateway.id}" }
    let(:params) do
      { merchantReference: order.number,
        skinCode: "xxxxxxxx",
        shopperLocale: "en_GB",
        paymentMethod: payment_method,
        authResult: auth_result,
        pspReference:  psp_reference,
        merchantSig: "erewrwerewrewrwer",
        merchantReturnData: merchantReturnData
      }
    end

    shared_examples "payment is successful" do
      it "changes the order state to completed" do
        subject
        order.reload
        expect(order).to have_attributes(
          state: "complete",
          payment_state: "balance_due",
          shipment_state: "pending"
        )
      end

      it "has pending payments" do
        expect(order.payments).to all be_pending
      end

      it "redirects to the order complete page" do
        is_expected.to have_http_status(:redirect).
          and redirect_to order_path(order)
      end

      it "creates a payment" do
        subject
        expect(order.reload.payments.count).to eq 1
      end

      context "and the order cannot complete" do
        before do
          expect(order).to receive(complete).and_return(false)
        end

        it "voids the payment"
      end
    end

    shared_examples "payment is not successful" do
      it "does not change order state" do
        expect{ subject }.to_not change{ order.state }
      end

      it "redirects to the order payment page" do
        is_expected.to have_http_status(:redirect).
          and redirect_to checkout_state_path("payment")
      end
    end

    context "when the payment is AUTHORISED" do
      include_examples "payment is successful"

      let(:auth_result) { "AUTHORISED" }

      context "and the authorisation notification has already been received" do
        let(:payment_method) { notification.payment_method }

        let(:notification) do
          create(
            :notification,
            :auth,
            processed: true,
            psp_reference: psp_reference,
            merchant_reference: order.number)
        end

        # there will already be a payment and source created at this point
        before do
          source =
            create(:hpp_source, psp_reference: psp_reference, order: order)

          create(:hpp_payment, source: source, order: order)

          order.contents.advance
          order.complete
        end

        it { expect { subject }.to_not change { order.payments.count }.from 1 }

        it "updates the source" do
          expect(order.payments.last.source).to have_attributes(
            auth_result: "AUTHORISED",
            skin_code: "XXXXXXXX"
          )
        end

        include_examples "payment is successful"
      end
    end

    context "when the payment is PENDING" do
      include_examples "payment is successful"
      let(:auth_result) { "PENDING" }
    end

    context "when the payment is CANCELLED" do
      include_examples "payment is not successful"
      let(:auth_result) { "CANCELLED" }
    end

    context "when the payment is REFUSED" do
      include_examples "payment is not successful"
      let(:auth_result) { "REFUSED" }
    end
  end

  describe "POST authorise3d" do
    include_context "mock adyen client",
      success: true,
      psp_reference: "8888888888888888"

    subject(:action) { post :authorise3d, params: params }

    let!(:cc_gateway) { create :adyen_cc_gateway, auto_capture: true }

    let(:payment) do
      create(
        :adyen_cc_payment,
        amount: order.total,
        state: payment_state,
        response_code: "8813824003752247",
        payment_method: cc_gateway,
        order: order
      )
    end

    let!(:redirect_response) do
      Spree::Adyen::RedirectResponse.create!(payment: payment, md: md)
    end

    let(:md) { "X/C2Fsz+BtrXBXJ5LUJN" }
    let(:params) { { MD: md, PaRes: "eNqtmFmTo0iSgN" } }

    # A duplicate 3DS return (browser refresh, duplicated redirect) used to
    # downgrade an already captured payment back to `pending` and fire a second
    # capture, which Adyen refuses, leaving the payment stuck in `processing`.
    shared_examples "does not re-run the 3DS authorization" do
      it "does not send a second authorization to Adyen" do
        expect(client).to_not receive(:authorise_payment_3dsecure)
        action
      end

      it "does not send a second capture to Adyen" do
        expect(client).to_not receive(:capture_payment)
        action
      end

      it "does not change the payment state" do
        expect { action }.to keep { payment.reload.state }
      end

      it "does not change the response code" do
        expect { action }.to keep { payment.reload.response_code }
      end
    end

    context "when the payment is still waiting on 3DS" do
      let(:payment_state) { "failed" }

      it "authorizes the payment with Adyen" do
        action
        expect(client).to have_received(:authorise_payment_3dsecure)
      end

      it "captures the payment" do
        expect { action }.
          to change { payment.reload.state }.
          from("failed").
          to("processing")
      end

      it "stores the psp reference of the 3DS authorization" do
        expect { action }.
          to change { payment.reload.response_code }.
          to("8888888888888888")
      end

      it "completes the order" do
        expect { action }.to change { order.reload.state }.to "complete"
      end

      it "redirects to the order" do
        is_expected.to have_http_status(:redirect).
          and redirect_to order_path(order)
      end
    end

    context "when the payment has already been completed" do
      let(:payment_state) { "completed" }

      include_examples "does not re-run the 3DS authorization"

      it "does not record a payment state change" do
        expect { action }.to keep { payment.state_changes.count }
      end

      it "completes the order and redirects to it" do
        expect { action }.to change { order.reload.state }.to "complete"
        is_expected.to redirect_to order_path(order)
      end

      context "and the order is already complete" do
        before do
          order.contents.advance
          order.complete
        end

        include_examples "does not re-run the 3DS authorization"

        it "redirects to the order" do
          is_expected.to have_http_status(:redirect).
            and redirect_to order_path(order)
        end
      end
    end

    context "when the payment is already being captured" do
      let(:payment_state) { "processing" }

      include_examples "does not re-run the 3DS authorization"
    end

    # Either a stale or replayed 3DS return, or the shopper re-entered the
    # checkout and `invalidate_old_payments` destroyed the redirect response.
    context "when the MD does not match a redirect response" do
      let(:payment_state) { "failed" }
      let(:params) { { MD: "some-unknown-md", PaRes: "eNqtmFmTo0iSgN" } }

      it "does not raise" do
        expect { action }.to_not raise_error
      end

      it "redirects to the cart" do
        is_expected.to have_http_status(:redirect).
          and redirect_to cart_path
      end

      it "does not touch the payment" do
        expect { action }.to keep { payment.reload.state }
      end
    end
  end

  # Inherited from Spree::AdyenController, so we exercise it here through a real
  # request to one of its subclasses.
  describe "Sentry critical path tagging" do
    subject(:action) { get :confirm, params: params }

    let(:params) do
      { merchantReference: order.number,
        skinCode: "xxxxxxxx",
        shopperLocale: "en_GB",
        paymentMethod: "amex",
        authResult: "AUTHORISED",
        pspReference: "8813824003752247",
        merchantSig: "erewrwerewrewrwer",
        merchantReturnData: "#{order.guest_token}|#{gateway.id}" }
    end

    context "when Sentry is defined" do
      it "tags the request with the checkout critical path" do
        sentry = class_double("Sentry").as_stubbed_const
        expect(sentry).to receive(:set_tags).with(critical_path: "checkout")

        action
      end
    end

    context "when Sentry is not defined" do
      before { hide_const("Sentry") if defined?(Sentry) }

      it "does not raise" do
        expect { action }.not_to raise_error
      end
    end
  end
end
