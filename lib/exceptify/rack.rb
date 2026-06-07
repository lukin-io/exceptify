# frozen_string_literal: true

require "exceptify"

module Exceptify
  class Rack
    class CascadePassException < RuntimeError; end

    attr_reader :configuration

    def initialize(app, options = {})
      @app = app
      @dispatcher = options.delete(:dispatcher)
      @configuration = options.delete(:configuration)
      @ignore_cascade_pass = options.delete(:ignore_cascade_pass) { true }

      return if @dispatcher
      return if options.empty? && @configuration.nil?

      @configuration ||= Exceptify.configuration.copy
      apply_options(@configuration, options)
      @dispatcher = Dispatcher.new(@configuration)
    end

    def call(env)
      _, headers, = response = @app.call(env)

      if !@ignore_cascade_pass && headers["X-Cascade"] == "pass"
        msg = "This exception means that the preceding Rack middleware set the 'X-Cascade' header to 'pass' -- in " \
              "Rails, this often means that the route was not found (404 error)."
        raise CascadePassException, msg
      end

      response
    rescue Exception => e # standard:disable Lint/RescueException
      env["exceptify.delivered"] = true if dispatcher.notify_exception(e, env: env)

      raise e unless e.is_a?(CascadePassException)

      response
    end

    private

    def dispatcher
      @dispatcher || Exceptify
    end

    def apply_options(configuration, options)
      configuration.ignored_exceptions = options.delete(:ignore_exceptions) if options.key?(:ignore_exceptions)
      configuration.error_grouping = options.delete(:error_grouping) if options.key?(:error_grouping)
      configuration.error_grouping_period = options.delete(:error_grouping_period) if options.key?(:error_grouping_period)
      configuration.notification_trigger = options.delete(:notification_trigger) if options.key?(:notification_trigger)

      if options.key?(:error_grouping_cache)
        configuration.error_grouping_cache = options.delete(:error_grouping_cache)
      elsif defined?(Rails) && Rails.respond_to?(:cache)
        configuration.error_grouping_cache = Rails.cache
      end

      apply_ignore_options(configuration, options)

      options.each do |notifier_name, opts|
        configuration.register_notifier(notifier_name, opts)
      end
    end

    def apply_ignore_options(configuration, options)
      if options.key?(:ignore_if)
        rack_ignore = options.delete(:ignore_if)
        configuration.ignore_if do |exception, opts|
          opts.key?(:env) && rack_ignore.call(opts[:env], exception)
        end
      end

      if options.key?(:ignore_notifier_if)
        rack_ignore_by_notifier = options.delete(:ignore_notifier_if)
        rack_ignore_by_notifier.each do |notifier, proc|
          configuration.ignore_notifier_if(notifier) do |exception, opts|
            opts.key?(:env) && proc.call(opts[:env], exception)
          end
        end
      end

      configuration.ignore_crawlers(options.delete(:ignore_crawlers)) if options.key?(:ignore_crawlers)
    end
  end
end
