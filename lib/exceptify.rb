# frozen_string_literal: true

require "exceptify/version"
require "exceptify/base_notifier"
require "exceptify/configuration"
require "exceptify/dispatcher"
require "exceptify/notification"
require "exceptify/request_context"

module Exceptify
  autoload :BacktraceCleaner, "exceptify/modules/backtrace_cleaner"
  autoload :Formatter, "exceptify/modules/formatter"

  autoload :Rack, "exceptify/rack"
  autoload :Notifier, "exceptify/notifier"
  autoload :EmailNotifier, "exceptify/email_notifier"
  autoload :WebhookNotifier, "exceptify/webhook_notifier"
  autoload :SlackNotifier, "exceptify/slack_notifier"
  autoload :TeamsNotifier, "exceptify/teams_notifier"
  autoload :SnsNotifier, "exceptify/sns_notifier"
  autoload :DatadogNotifier, "exceptify/datadog_notifier"

  class UndefinedNotifierError < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset!
      self.configuration = Configuration.new
    end

    def reset_notifiers!
      configuration.reset!
    end

    def testing_mode!
      configuration.testing_mode!
    end

    def notify_exception(exception, options = {}, &block)
      Dispatcher.new(configuration).notify_exception(exception, options, &block)
    end

    def register_notifier(name, notifier_or_options)
      configuration.register_notifier(name, notifier_or_options)
    end
    alias_method :add_notifier, :register_notifier

    def unregister_notifier(name)
      configuration.unregister_notifier(name)
    end

    def registered_notifier(name)
      configuration.registered_notifier(name)
    end

    def notifiers
      configuration.notifiers
    end

    def ignore_if(&block)
      configuration.ignore_if(&block)
    end

    def ignore_notifier_if(notifier, &block)
      configuration.ignore_notifier_if(notifier, &block)
    end

    def ignore_crawlers(crawlers)
      configuration.ignore_crawlers(crawlers)
    end

    def clear_ignore_conditions!
      configuration.clear_ignore_conditions!
    end

    def ignored?(exception, options)
      configuration.ignored?(exception, options)
    end

    def notifier_ignored?(exception, options, notifier:)
      configuration.notifier_ignored?(exception, options, notifier: notifier)
    end

    def ignored_exception?(ignore_array, exception)
      configuration.ignored_exception?(ignore_array, exception)
    end

    def error_count(error_key)
      configuration.error_count(error_key)
    end

    def save_error_count(error_key, count)
      configuration.save_error_count(error_key, count)
    end

    def group_error!(exception, options)
      configuration.group_error!(exception, options)
    end

    def send_notification?(exception, count)
      configuration.send_notification?(exception, count)
    end

    def logger
      configuration.logger
    end

    def logger=(logger)
      configuration.logger = logger
    end

    def ignored_exceptions
      configuration.ignored_exceptions
    end

    def ignored_exceptions=(ignored_exceptions)
      configuration.ignored_exceptions = ignored_exceptions
    end

    def testing_mode
      configuration.testing_mode
    end

    def testing_mode=(testing_mode)
      configuration.testing_mode = testing_mode
    end

    def error_grouping
      configuration.error_grouping
    end

    def error_grouping=(error_grouping)
      configuration.error_grouping = error_grouping
    end

    def error_grouping_period
      configuration.error_grouping_period
    end

    def error_grouping_period=(error_grouping_period)
      configuration.error_grouping_period = error_grouping_period
    end

    def notification_trigger
      configuration.notification_trigger
    end

    def notification_trigger=(notification_trigger)
      configuration.notification_trigger = notification_trigger
    end

    def error_grouping_cache
      configuration.error_grouping_cache
    end

    def error_grouping_cache=(error_grouping_cache)
      configuration.error_grouping_cache = error_grouping_cache
    end

    def fallback_cache_store
      configuration.fallback_cache_store
    end

    def fallback_cache_store=(fallback_cache_store)
      configuration.fallback_cache_store = fallback_cache_store
    end
  end
end
