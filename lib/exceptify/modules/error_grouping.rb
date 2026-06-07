# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/concern"

module Exceptify
  module ErrorGrouping
    extend ActiveSupport::Concern

    class Service
      attr_reader :cache, :fallback_cache_store, :period, :notification_trigger, :logger

      def initialize(cache:, fallback_cache_store:, period:, notification_trigger:, logger:)
        @cache = cache
        @fallback_cache_store = fallback_cache_store
        @period = period
        @notification_trigger = notification_trigger
        @logger = logger
      end

      def error_count(error_key)
        count =
          begin
            cache_store.read(error_key)
          rescue => e
            log_cache_error(cache_store, e, :read)
            fallback_cache_store.read(error_key)
          end

        count&.to_i
      end

      def save_error_count(error_key, count)
        cache_store.write(error_key, count, expires_in: period)
      rescue => e
        log_cache_error(cache_store, e, :write)
        fallback_cache_store.write(error_key, count, expires_in: period)
      end

      def group_error!(exception, options)
        message_based_key = key_for_message(exception)
        accumulated_errors_count = 1

        if (count = error_count(message_based_key))
          accumulated_errors_count = count + 1
          save_error_count(message_based_key, accumulated_errors_count)
        else
          backtrace_based_key = key_for_backtrace(exception)

          if (count = error_count(backtrace_based_key))
            accumulated_errors_count = count + 1
            save_error_count(backtrace_based_key, accumulated_errors_count)
          else
            save_error_count(backtrace_based_key, accumulated_errors_count)
            save_error_count(message_based_key, accumulated_errors_count)
          end
        end

        options[:accumulated_errors_count] = accumulated_errors_count
      end

      def send_notification?(exception, count)
        if notification_trigger.respond_to?(:call)
          notification_trigger.call(exception, count)
        else
          factor = Math.log2(count)
          factor.to_i == factor
        end
      end

      private

      def cache_store
        cache || fallback_cache_store
      end

      def key_for_message(exception)
        "exception:#{Zlib.crc32("#{exception.class.name}\nmessage:#{exception.message}")}"
      end

      def key_for_backtrace(exception)
        "exception:#{Zlib.crc32("#{exception.class.name}\npath:#{exception.backtrace.try(:first)}")}"
      end

      def log_cache_error(cache, exception, action)
        logger.warn(
          "#{cache.inspect} failed to #{action}, reason: #{exception.message}. Falling back to memory cache store."
        )
      end
    end

    included do
      mattr_accessor :error_grouping
      self.error_grouping = false

      mattr_accessor :error_grouping_period
      self.error_grouping_period = 5.minutes

      mattr_accessor :notification_trigger

      mattr_accessor :error_grouping_cache
    end

    module ClassMethods
      # Fallback to the memory store while the specified cache store doesn't work
      #
      def fallback_cache_store
        @fallback_cache_store ||= ActiveSupport::Cache::MemoryStore.new
      end

      def error_count(error_key)
        count =
          begin
            error_grouping_cache.read(error_key)
          rescue => e
            log_cache_error(error_grouping_cache, e, :read)
            fallback_cache_store.read(error_key)
          end

        count&.to_i
      end

      def save_error_count(error_key, count)
        error_grouping_cache.write(error_key, count, expires_in: error_grouping_period)
      rescue => e
        log_cache_error(error_grouping_cache, e, :write)
        fallback_cache_store.write(error_key, count, expires_in: error_grouping_period)
      end

      def group_error!(exception, options)
        message_based_key = "exception:#{Zlib.crc32("#{exception.class.name}\nmessage:#{exception.message}")}"
        accumulated_errors_count = 1

        if (count = error_count(message_based_key))
          accumulated_errors_count = count + 1
          save_error_count(message_based_key, accumulated_errors_count)
        else
          backtrace_based_key =
            "exception:#{Zlib.crc32("#{exception.class.name}\npath:#{exception.backtrace.try(:first)}")}"

          if (count = error_grouping_cache.read(backtrace_based_key))
            accumulated_errors_count = count + 1
            save_error_count(backtrace_based_key, accumulated_errors_count)
          else
            save_error_count(backtrace_based_key, accumulated_errors_count)
            save_error_count(message_based_key, accumulated_errors_count)
          end
        end

        options[:accumulated_errors_count] = accumulated_errors_count
      end

      def send_notification?(exception, count)
        if notification_trigger.respond_to?(:call)
          notification_trigger.call(exception, count)
        else
          factor = Math.log2(count)
          factor.to_i == factor
        end
      end

      private

      def log_cache_error(cache, exception, action)
        "#{cache.inspect} failed to #{action}, reason: #{exception.message}. Falling back to memory cache store."
      end
    end
  end
end
