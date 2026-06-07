# frozen_string_literal: true

require "active_support/core_ext/time"
require "action_dispatch"
require "exceptify/notification"

module Exceptify
  class Formatter
    include Exceptify::BacktraceCleaner

    attr_reader :app_name

    def initialize(exception_or_notification, opts = {})
      @notification = if exception_or_notification.is_a?(Notification)
        exception_or_notification
      else
        Notification.new(exception_or_notification, opts, backtrace_cleaner: self)
      end
      @exception = notification.exception
      @errors_count = notification.options[:accumulated_errors_count].to_i
      @app_name = notification.app_name
    end

    #
    # :warning: Error occurred in production :warning:
    # :warning: Error occurred :warning:
    #
    def title
      env = notification.env_name

      if env
        "⚠️ Error occurred in #{env} ⚠️"
      else
        "⚠️ Error occurred ⚠️"
      end
    end

    #
    # A *NoMethodError* occurred.
    # 3 *NoMethodError* occurred.
    # A *NoMethodError* occurred in *home#index*.
    #
    def subtitle
      errors_text = if errors_count > 1
        errors_count
      else
        /^[aeiou]/i.match?(exception.class.to_s) ? "An" : "A"
      end

      in_action = " in *#{controller_and_action}*" if controller

      "#{errors_text} *#{exception.class}* occurred#{in_action}."
    end

    #
    #
    # *Request:*
    # ```
    # * url : https://www.example.com/
    # * http_method : GET
    # * ip_address : 127.0.0.1
    # * parameters : {"controller"=>"home", "action"=>"index"}
    # * timestamp : 2019-01-01 00:00:00 UTC
    # ```
    #
    def request_message
      request = notification.request_context.request
      return unless request

      [
        "```",
        "* url : #{request.original_url}",
        "* http_method : #{request.method}",
        "* ip_address : #{request.remote_ip}",
        "* parameters : #{request.filtered_parameters}",
        "* timestamp : #{notification.timestamp}",
        "```"
      ].join("\n")
    end

    #
    #
    # *Backtrace:*
    # ```
    # * app/controllers/my_controller.rb:99:in `specific_function'
    # * app/controllers/my_controller.rb:70:in `specific_param'
    # * app/controllers/my_controller.rb:53:in `my_controller_params'
    # ```
    #
    def backtrace_message
      backtrace = notification.backtrace

      return if backtrace.empty?

      text = []

      text << "```"
      backtrace.first(3).each { |line| text << "* #{line}" }
      text << "```"

      text.join("\n")
    end

    #
    # home#index
    #
    def controller_and_action
      notification.controller_and_action
    end

    private

    attr_reader :exception, :errors_count, :notification

    def controller
      notification.controller
    end
  end
end
