module Spree
  module Adyen
    # Used when we have to override functionally inside spree, usually payments,
    # that is a conditional flow only on adyen payments.
    module PaymentCheck
      def ratepay? payment = self
        payment.payment_method.class == Spree::PaymentMethod::AdyenRatepay
      end

      def hpp_payment? payment = self
        payment.source.class == Spree::Adyen::HPPSource
      end

      def adyen_cc_payment? payment = self
        payment.payment_method.class == Spree::PaymentMethod::AdyenCreditCard
      end
    end
  end
end
