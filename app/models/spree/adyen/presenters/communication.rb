module Spree
  module Adyen
    module Presenters
      # Factory for creating communication presenters, based on a payment
      # source.
      class Communication < SimpleDelegator
        PRESENTERS = [
          ::Spree::Adyen::Presenters::Communications::AdyenNotification,
          ::Spree::Adyen::Presenters::Communications::HPPSource,
          ::Spree::Adyen::Presenters::Communications::RatepaySource,
          ::Spree::Adyen::Presenters::Communications::LogEntry
        ].freeze

        def self.from_source source
          ([source] + source.notifications + source.payment.log_entries).
            sort_by(&:created_at).
            map { |x| build x }
        end

        def self.from_payment payment
          notifications = AdyenNotification.where('psp_reference = ? or original_reference = ?', payment.transaction_id, payment.transaction_id)
          (notifications + payment.log_entries).
            sort_by(&:created_at).
            map { |x| build x }
        end

        def self.build object
          presenter_for(object).new(object)
        end

        def self.presenter_for object
          PRESENTERS.detect do |klass|
            klass.applicable? object
          end || fail("Couldn't map to a communication type")
        end
      end
    end
  end
end
