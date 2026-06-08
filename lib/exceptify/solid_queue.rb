# frozen_string_literal: true

require "active_job"
require "active_support/notifications"
require "exceptify"

module Exceptify
  module SolidQueue
    ADAPTER_NAME = "solid_queue"
    EVENT_NAME = "perform.active_job"
    JOB_ATTRIBUTES = %i[
      job_id
      provider_job_id
      queue_name
      priority
      arguments
      executions
      exception_executions
      locale
      timezone
      enqueued_at
      scheduled_at
    ].freeze

    class << self
      def install
        return if installed?

        @subscription = ActiveSupport::Notifications.subscribe(EVENT_NAME) do |*args|
          notify(ActiveSupport::Notifications::Event.new(*args))
        end
      end

      def installed?
        !!@subscription
      end

      def notify(event)
        exception = event.payload[:exception_object]
        job = event.payload[:job]

        return unless exception && solid_queue_job?(job)

        Exceptify.notify_exception(exception, data: {solid_queue: job_data(job)})
      end

      private

      def solid_queue_job?(job)
        queue_adapter_name(job) == ADAPTER_NAME
      end

      def queue_adapter_name(job)
        job.class.queue_adapter_name if job && job.class.respond_to?(:queue_adapter_name)
      end

      def job_data(job)
        {adapter: queue_adapter_name(job), job_class: job.class.name}.tap do |data|
          JOB_ATTRIBUTES.each do |attribute|
            data[attribute] = job.public_send(attribute) if job.respond_to?(attribute)
          end
        end.compact
      end
    end
  end
end

Exceptify::SolidQueue.install
