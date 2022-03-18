# Because adyen payment modifications are delayed we don't actually know if
# the request succeeded after doing it. For that reason we can't use the
# standard capture! and friends as they change the payment state and would
# result is false positives (payment could fail after capture).
module Spree
  module Adyen
    module Payment
      include Spree::Adyen::PaymentCheck

      def self.prepended(mod)
        mod.has_one :redirect_response,
          class_name: "Spree::Adyen::RedirectResponse",
          inverse_of: :payment,
          dependent: :destroy

        mod.after_create :authorise_on_create, if: :should_authorise?
      end

      # Spree::Payment#process will call purchase! for payment methods with
      # auto_capture enabled. Since we authorize credit cards in the payment
      # step already, we just need to capture the payment here.
      def purchase!
        if ratepay?
          capture!
        elsif adyen_cc_payment?
          authorize!
          capture!
        else
          super
        end
      end

      # capture! :: bool | error
      def capture!
        if hpp_payment? || adyen_cc_payment? || ratepay?
          amount = money.money.cents
          process do
            payment_method.send(
              :capture, amount, response_code, gateway_options)
          end
        else
          super
        end
      end

      # credit! :: bool | error
      #
      # Issue a request to credit the payment, this does NOT perform validation
      # on the amount to be credited, which is assumed to have been done prior
      # to this.
      #
      # credit! is only implemented for hpp payments, because of the delayed
      # manner of Adyen api communications. If this method is called on a
      # payment that is not from Adyen then it should fail. This is crummy way
      # of getting around the fact that Payment methods cannot specifiy these
      # methods.
      def credit! amount, options
        if hpp_payment? || adyen_cc_payment?
          process { payment_method.credit(amount, response_code, options) }
        else
          fail NotImplementedError, "Spree::Payment does not implement credit!"
        end
      end

      # cancel! :: bool | error
      #
      # Borrowed from handle_void_response, this has been modified so that it
      # won't actually void the payment _yet_.
      def cancel!
        if hpp_payment? || adyen_cc_payment?
          if source.respond_to?(:requires_manual_refund?) && source.requires_manual_refund?
            log_manual_refund
          else
            process { payment_method.cancel response_code }
          end
        else
          super
        end
      end

      def gateway_options
        if request_env
          super.merge({
            HTTP_USER_AGENT: request_env["HTTP_USER_AGENT"],
            HTTP_ACCEPT: request_env["HTTP_ACCEPT"]
          })
        else
          super
        end
      end

      private

      def authorise_on_create
        payment_method.authorise_new_payment(self)
      end

      # With 3D Secure, if the user backs out and re-enters the checkout flow,
      # we should destroy old 3DS responses to prevent accidentally using them.
      def invalidate_old_payments
        unless store_credit?
          Spree::Adyen::RedirectResponse.where(payment: order.payments).destroy_all
        end
        super
      end

      def log_manual_refund
        message = I18n.t("solidus-adyen.manual_refund.log_message")
        record_response(
          OpenStruct.new(
            success?: false,
            message: message))
      end

      def process &block
        response = nil

        Spree::Payment.transaction do
          protect_from_connection_error do
            started_processing!
            response = yield(block)
            fail ActiveRecord::Rollback unless response.success?
          end
        end

        record_response(response)

        if response.success?
          # The payments controller's fire action expects a truthy value to
          # indicate success
          true
        else
          # this is done to be consistent with capture, but we might actually
          # want them to just return to the previous state
          gateway_error(response)
        end
      end

      # The response will be a failure for redirects, which will prevent the
      # order from completing and should allow us to transition it after
      # the user is redirected back from the 3DS page
      def handle_response(response, success_state, failure_state)
        if response.is_a?(Spree::Adyen::BillingResponse) && response.redirect?
          self.create_redirect_response!(
            md: response.md,
            pa_request: response.pa_request,
            issuer_url: response.issuer_url,
            psp_reference: response.psp_reference
          )
        end

        super
      end

      def should_authorise?
        ratepay? && amount > 0
      end
    end
  end
end
