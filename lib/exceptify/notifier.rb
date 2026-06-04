# frozen_string_literal: true

require "active_support/deprecation"

module Exceptify
  class Notifier
    def self.exceptify(env, exception, options = {})
      ActiveSupport::Deprecation.warn(
        "Please use Exceptify.notify_exception(exception, options.merge(env: env))."
      )
      Exceptify.registered_notifier(:email).create_email(exception, options.merge(env: env))
    end

    def self.background_exceptify(exception, options = {})
      ActiveSupport::Deprecation.warn "Please use Exceptify.notify_exception(exception, options)."
      Exceptify.registered_notifier(:email).create_email(exception, options)
    end
  end
end
