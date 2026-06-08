# frozen_string_literal: true

require "test_helper"
require "active_job"
require "exceptify/solid_queue"

class SolidQueueTest < ActiveSupport::TestCase
  setup do
    @previous_adapter = ActiveJob::Base.queue_adapter
    @previous_logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = Logger.new(nil)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_adapter
    ActiveJob::Base.logger = @previous_logger
  end

  test "notifies exception when a solid queue job fails" do
    ActiveJob::Base.queue_adapter = SolidQueueAdapter.new

    Exceptify.expects(:notify_exception).with do |exception, options|
      solid_queue_data = options[:data][:solid_queue]

      exception.is_a?(RuntimeError) &&
        exception.message == "Solid Queue failed!" &&
        solid_queue_data[:job_class] == "SolidQueueTest::BadJob" &&
        solid_queue_data[:job_id].present? &&
        solid_queue_data[:queue_name] == "critical" &&
        solid_queue_data[:arguments] == [42] &&
        solid_queue_data[:executions] == 1 &&
        solid_queue_data[:timezone] == "UTC" &&
        solid_queue_data.key?(:exception_executions)
    end

    error = assert_raises(RuntimeError) { BadJob.perform_now(42) }
    assert_equal "Solid Queue failed!", error.message
  end

  test "does not notify exception when a solid queue job succeeds" do
    ActiveJob::Base.queue_adapter = SolidQueueAdapter.new

    Exceptify.expects(:notify_exception).never

    assert_equal true, GoodJob.perform_now
  end

  test "does not notify exception for other active job adapters" do
    ActiveJob::Base.queue_adapter = :inline

    Exceptify.expects(:notify_exception).never

    assert_raises(RuntimeError) { BadJob.perform_now(42) }
  end

  test "does not notify exception handled by active job" do
    ActiveJob::Base.queue_adapter = SolidQueueAdapter.new

    Exceptify.expects(:notify_exception).never

    assert_equal RuntimeError, HandledJob.perform_now.class
  end

  class SolidQueueAdapter
    def queue_adapter_name
      "solid_queue"
    end

    def enqueue(job)
      job.perform_now
    end

    def enqueue_at(job, _timestamp)
      enqueue(job)
    end
  end

  class BadJob < ActiveJob::Base
    queue_as :critical

    def perform(account_id)
      raise "Solid Queue failed!" if account_id == 42
    end
  end

  class GoodJob < ActiveJob::Base
    def perform
      true
    end
  end

  class HandledJob < ActiveJob::Base
    rescue_from RuntimeError do |exception|
      exception
    end

    def perform
      raise "Handled job failed!"
    end
  end
end
