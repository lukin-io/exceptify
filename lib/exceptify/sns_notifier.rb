# frozen_string_literal: true

module Exceptify
  class SnsNotifier < BaseNotifier
    def initialize(options)
      options = options.dup
      super

      @notifier = options.delete(:client) || build_client(options)
      @options = default_options.merge(options)
    end

    def call(exception, custom_opts = {})
      custom_options = options.merge(custom_opts)
      notification = Notification.new(exception, custom_options)

      subject = build_subject(notification, custom_options)
      message = build_message(notification, custom_options)

      notifier.publish(
        topic_arn: custom_options[:topic_arn],
        message: message,
        subject: subject
      )
    end

    private

    attr_reader :notifier, :options

    def build_client(options)
      raise ArgumentError, "You must provide 'region' option" unless options[:region]
      raise ArgumentError, "You must provide 'access_key_id' option" unless options[:access_key_id]
      raise ArgumentError, "You must provide 'secret_access_key' option" unless options[:secret_access_key]
      raise ArgumentError, "SNS notifier requires the 'aws-sdk-sns' gem" unless defined?(::Aws::SNS::Client)

      Aws::SNS::Client.new(
        region: options[:region],
        access_key_id: options[:access_key_id],
        secret_access_key: options[:secret_access_key]
      )
    end

    def build_subject(notification, options)
      subject =
        "#{options[:sns_prefix]} - #{accumulated_exception_name(notification, options)} occurred"
      (subject.length > 120) ? subject[0...120] + "..." : subject
    end

    def build_message(notification, options)
      exception = notification.exception
      exception_name = accumulated_exception_name(notification, options)

      if notification.env.nil?
        text = "#{exception_name} occured in background\n"
        data = notification.data
      else
        env = notification.env

        kontroller = env["action_controller.instance"]
        data = notification.data
        request = "#{env["REQUEST_METHOD"]} <#{env["REQUEST_URI"]}>"

        text = "#{exception_name} occurred while #{request}"
        text += " was processed by #{kontroller.controller_name}##{kontroller.action_name}\n" if kontroller
      end

      text += "Exception: #{exception.message}\n"
      text += "Hostname: #{notification.hostname}\n"
      text += "Data: #{data}\n"

      return text if notification.backtrace.empty?

      formatted_backtrace = notification.backtrace.first(options[:backtrace_lines]).join("\n").to_s
      text + "Backtrace:\n#{formatted_backtrace}\n"
    end

    def accumulated_exception_name(notification, options)
      errors_count = options[:accumulated_errors_count].to_i
      exception = notification.exception

      measure_word = if errors_count > 1
        errors_count
      else
        /^[aeiou]/i.match?(exception.class.to_s) ? "An" : "A"
      end

      "#{measure_word} #{exception.class}"
    end

    def default_options
      {
        sns_prefix: "[ERROR]",
        backtrace_lines: 10
      }
    end
  end
end
