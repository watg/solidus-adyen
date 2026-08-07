module Spree
  class AdyenController < StoreController
    before_action :tag_sentry_critical_path

    private

    def tag_sentry_critical_path
      Sentry.set_tags(critical_path: 'checkout') if defined?(Sentry)
    end
  end
end
