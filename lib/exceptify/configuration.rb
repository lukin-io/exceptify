# frozen_string_literal: true

require "logger"
require "active_support/core_ext/numeric/time"
require "active_support/cache"
require "exceptify/notifier_registry"
require "exceptify/modules/error_grouping"

module Exceptify
  class Configuration
    attr_accessor :logger,
      :ignored_exceptions,
      :testing_mode,
      :error_grouping,
      :error_grouping_period,
      :notification_trigger,
      :error_grouping_cache,
      :fallback_cache_store

    attr_reader :notifier_registry

    DEFAULT_IGNORED_EXCEPTIONS = %w[
      ActiveRecord::RecordNotFound Mongoid::Errors::DocumentNotFound AbstractController::ActionNotFound
      ActionController::RoutingError ActionController::UnknownFormat ActionController::UrlGenerationError
      ActionDispatch::Http::MimeNegotiation::InvalidType Rack::Utils::InvalidParameterError
    ].freeze

    def initialize(
      logger: Logger.new($stdout),
      ignored_exceptions: DEFAULT_IGNORED_EXCEPTIONS,
      notifier_registry: NotifierRegistry.new,
      error_grouping_cache: nil,
      fallback_cache_store: ActiveSupport::Cache::MemoryStore.new
    )
      @logger = logger
      @ignored_exceptions = ignored_exceptions.dup
      @testing_mode = false
      @error_grouping = false
      @error_grouping_period = 5.minutes
      @notification_trigger = nil
      @error_grouping_cache = error_grouping_cache
      @fallback_cache_store = fallback_cache_store
      @notifier_registry = notifier_registry
      @ignores = []
      @by_notifier_ignores = {}
    end

    def copy
      self.class.new(
        logger: logger,
        ignored_exceptions: ignored_exceptions,
        notifier_registry: notifier_registry.copy,
        error_grouping_cache: error_grouping_cache,
        fallback_cache_store: fallback_cache_store
      ).tap do |configuration|
        configuration.testing_mode = testing_mode
        configuration.error_grouping = error_grouping
        configuration.error_grouping_period = error_grouping_period
        configuration.notification_trigger = notification_trigger
        ignores.each { |condition| configuration.ignore_if(&condition) }
        by_notifier_ignores.each { |notifier, condition| configuration.ignore_notifier_if(notifier, &condition) }
      end
    end

    def reset!
      notifier_registry.clear
      clear_ignore_conditions!
      self.error_grouping = false
      self.notification_trigger = nil
      self.error_grouping_cache = nil
      fallback_cache_store.clear if fallback_cache_store.respond_to?(:clear)
    end

    def testing_mode!
      self.testing_mode = true
    end

    def register_notifier(name, notifier_or_options)
      notifier_registry.register(name, notifier_or_options)
    end
    alias_method :add_notifier, :register_notifier

    def unregister_notifier(name)
      notifier_registry.unregister(name)
    end

    def registered_notifier(name)
      notifier_registry.fetch(name)
    end

    def notifiers
      notifier_registry.names
    end

    def ignore_if(&block)
      ignores << block
    end

    def ignore_notifier_if(notifier, &block)
      by_notifier_ignores[notifier] = block
    end

    def ignore_crawlers(crawlers)
      ignore_if do |_exception, opts|
        opts.key?(:env) && from_crawler(opts[:env], crawlers)
      end
    end

    def clear_ignore_conditions!
      ignores.clear
      by_notifier_ignores.clear
    end

    def ignored?(exception, options)
      ignores.any? { |condition| condition.call(exception, options) }
    rescue Exception => e # standard:disable Lint/RescueException
      raise e if testing_mode

      logger.warn(
        "An error occurred when evaluating an ignore condition. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      )
      false
    end

    def notifier_ignored?(exception, options, notifier:)
      return false unless by_notifier_ignores.key?(notifier)

      by_notifier_ignores[notifier].call(exception, options)
    rescue Exception => e # standard:disable Lint/RescueException
      raise e if testing_mode

      logger.warn(<<~"MESSAGE")
        An error occurred when evaluating a by-notifier ignore condition. #{e.class}: #{e.message}
        #{e.backtrace.join("\n")}
      MESSAGE
      false
    end

    def ignored_exception?(ignore_array, exception)
      all_ignored_exceptions = (Array(ignored_exceptions) + Array(ignore_array)).map(&:to_s)
      exception_ancestors = exception.singleton_class.ancestors.map(&:to_s)
      !(all_ignored_exceptions & exception_ancestors).empty?
    end

    def error_count(error_key)
      error_grouping_service.error_count(error_key)
    end

    def save_error_count(error_key, count)
      error_grouping_service.save_error_count(error_key, count)
    end

    def group_error!(exception, options)
      error_grouping_service.group_error!(exception, options)
    end

    def send_notification?(exception, count)
      error_grouping_service.send_notification?(exception, count)
    end

    protected

    attr_reader :ignores, :by_notifier_ignores

    private

    def error_grouping_service
      ErrorGrouping::Service.new(
        cache: error_grouping_cache,
        fallback_cache_store: fallback_cache_store,
        period: error_grouping_period,
        notification_trigger: notification_trigger,
        logger: logger
      )
    end

    def from_crawler(env, ignored_crawlers)
      agent = env["HTTP_USER_AGENT"]
      Array(ignored_crawlers).any? do |crawler|
        agent =~ Regexp.new(crawler)
      end
    end
  end
end
