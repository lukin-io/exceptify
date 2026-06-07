# frozen_string_literal: true

module Exceptify
  class Dispatcher
    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
    end

    def notify_exception(exception, options = {}, &block)
      options = options.dup

      return false if configuration.ignored_exception?(options[:ignore_exceptions], exception)
      return false if configuration.ignored?(exception, options)

      if configuration.error_grouping
        errors_count = configuration.group_error!(exception, options)
        return false unless configuration.send_notification?(exception, errors_count)
      end

      notification_fired = false
      selected_notifiers = options.delete(:notifiers) || configuration.notifiers
      [*selected_notifiers].each do |notifier|
        unless configuration.notifier_ignored?(exception, options, notifier: notifier)
          fire_notification(notifier, exception, options.dup, &block)
          notification_fired = true
        end
      end

      notification_fired
    end

    private

    def fire_notification(notifier_name, exception, options, &block)
      notifier = configuration.registered_notifier(notifier_name)
      notifier.call(exception, options, &block)
    rescue Exception => e # standard:disable Lint/RescueException
      raise e if configuration.testing_mode

      configuration.logger.warn(
        "An error occurred when sending a notification using '#{notifier_name}' notifier." \
        "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      )
      false
    end
  end
end
