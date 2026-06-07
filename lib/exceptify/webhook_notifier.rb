# frozen_string_literal: true

require "action_dispatch"
require "active_support/core_ext/time"

module Exceptify
  class WebhookNotifier < BaseNotifier
    def initialize(options)
      options = options.dup
      @http_client = options.delete(:http_client) || HTTParty
      super()
      self.base_options = options
      @default_options = options
    end

    def call(exception, options = {})
      notification = Notification.new(exception, options)
      env = notification.env

      options = options.reverse_merge(@default_options)
      url = options.delete(:url)
      raise ArgumentError, "You must provide 'url' option" if blank?(url)

      http_method = options.delete(:http_method) || :post

      options[:body] ||= {}
      options[:body][:server] = notification.hostname
      options[:body][:process] = Process.pid
      options[:body][:rails_root] = Rails.root if defined?(Rails) && Rails.respond_to?(:root)
      options[:body][:exception] = {
        error_class: exception.class.to_s,
        message: exception.message.inspect,
        backtrace: notification.backtrace
      }
      options[:body][:data] = notification.data

      unless env.nil?
        request = notification.request_context.request

        request_items = {
          url: request.original_url,
          http_method: request.method,
          ip_address: request.remote_ip,
          parameters: request.filtered_parameters,
          timestamp: notification.timestamp
        }

        options[:body][:request] = request_items
        options[:body][:session] = request.session
        options[:body][:environment] = request.filtered_env
      end
      send_notice(exception, options, nil, @default_options) do |_, _|
        @http_client.send(http_method, url, options)
      end
    end

    private

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
