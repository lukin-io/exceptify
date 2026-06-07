# frozen_string_literal: true

module Exceptify
  class SlackNotifier < BaseNotifier
    include Exceptify::BacktraceCleaner

    attr_accessor :notifier

    def initialize(options)
      options = options.dup
      fail_silently = options.delete(:fail_silently) { false }
      injected_notifier = options.delete(:notifier)
      super()
      self.base_options = options

      @ignore_data_if = options[:ignore_data_if]
      @backtrace_lines = options.fetch(:backtrace_lines, 10)
      @additional_fields = options[:additional_fields]
      @message_opts = options.fetch(:additional_parameters, {}).dup
      @color = @message_opts.delete(:color) { "danger" }

      @notifier = injected_notifier || build_notifier(options)
    rescue => e
      raise unless fail_silently

      log_configuration_error(e)
      @notifier = nil
    end

    def call(exception, options = {})
      notification = Notification.new(exception, options, backtrace_cleaner: self)
      clean_message = exception.message.tr("`", "'")
      attchs = attchs(notification, clean_message)

      return unless valid?

      args = [exception, options, clean_message, @message_opts.merge(attachments: attchs)]
      send_notice(*args) do |_msg, message_opts|
        message_opts[:channel] = options[:channel] if options.key?(:channel)

        @notifier.ping "", message_opts
      end
    end

    protected

    def valid?
      !@notifier.nil?
    end

    def deep_reject(hash, block)
      hash.each do |k, v|
        deep_reject(v, block) if v.is_a?(Hash)

        hash.delete(k) if block.call(k, v)
      end
    end

    private

    def build_notifier(options)
      webhook_url = options[:webhook_url]
      raise ArgumentError, "You must provide 'webhook_url' option" if blank?(webhook_url)
      unless defined?(::Slack::Notifier)
        raise ArgumentError, "Slack notifier requires the 'slack-notifier' gem"
      end

      Slack::Notifier.new(webhook_url, options)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def log_configuration_error(error)
      Exceptify.logger&.warn(
        "Slack notifier disabled: #{error.class}: #{error.message}"
      )
    end

    def attchs(notification, clean_message)
      text, data = information_from_notification(notification)
      backtrace = notification.backtrace
      fields = fields(notification, clean_message, backtrace, data)

      [color: @color, text: text, fields: fields, mrkdwn_in: %w[text fields]]
    end

    def information_from_notification(notification)
      errors_count = notification.options[:accumulated_errors_count].to_i
      exception_class = notification.exception.class

      measure_word = if errors_count > 1
        errors_count
      else
        /^[aeiou]/i.match?(exception_class.to_s) ? "An" : "A"
      end

      exception_name = "*#{measure_word}* `#{exception_class}`"
      env = notification.env
      data = notification.data

      notification.options[:headers] ||= {}
      notification.options[:headers]["Content-Type"] = "application/json"

      if env.nil?
        text = "#{exception_name} *occured in background*\n"
      else
        kontroller = env["action_controller.instance"]
        request = "#{env["REQUEST_METHOD"]} <#{env["REQUEST_URI"]}>"
        text = "#{exception_name} *occurred while* `#{request}`"
        text += " *was processed by* `#{kontroller.controller_name}##{kontroller.action_name}`" if kontroller
        text += "\n"
      end

      [text, data]
    end

    def fields(notification, clean_message, backtrace, data)
      fields = [
        {title: "Exception", value: clean_message},
        {title: "Hostname", value: notification.hostname}
      ]

      unless backtrace.empty?
        formatted_backtrace = "```#{backtrace.first(@backtrace_lines).join("\n")}```"
        fields << {title: "Backtrace", value: formatted_backtrace}
      end

      unless data.empty?
        deep_reject(data, @ignore_data_if) if @ignore_data_if.is_a?(Proc)
        data_string = data.map { |k, v| "#{k}: #{v}" }.join("\n")
        fields << {title: "Data", value: "```#{data_string}```"}
      end

      fields.concat(@additional_fields) if @additional_fields

      fields
    end
  end
end
