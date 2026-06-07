# frozen_string_literal: true

require "socket"
require "active_support/core_ext/time"
require "exceptify/request_context"

module Exceptify
  class Notification
    attr_reader :exception, :options, :request_context

    def initialize(exception, options = {}, clock: Time, hostname: -> { Socket.gethostname }, backtrace_cleaner: nil, **keyword_options)
      @exception = exception
      @options = options.merge(keyword_options)
      @clock = clock
      @hostname = hostname
      @backtrace_cleaner = backtrace_cleaner
      @request_context = @options[:request_context] || RequestContext.new(@options[:env])
    end

    def env
      request_context.env
    end

    def data
      request_context.exception_data.merge(options[:data] || {})
    end

    def backtrace
      return [] unless exception.backtrace
      return @backtrace_cleaner.clean_backtrace(exception) if @backtrace_cleaner

      exception.backtrace
    end

    def timestamp
      @clock.respond_to?(:current) ? @clock.current : @clock.now
    end

    def hostname
      @hostname.call
    end

    def app_name
      options[:app_name] || rails_app_name
    end

    def env_name
      Rails.env if defined?(::Rails) && ::Rails.respond_to?(:env)
    end

    def controller
      request_context.controller
    end

    def controller_and_action
      request_context.controller_and_action
    end

    private

    def rails_app_name
      return unless defined?(::Rails) && ::Rails.respond_to?(:application)

      if Rails::VERSION::MAJOR >= 6
        Rails.application.class.module_parent_name.underscore
      else
        Rails.application.class.parent_name.underscore
      end
    end
  end
end
