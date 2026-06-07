# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "success: merges request and explicit data" do
    env = Rack::MockRequest.env_for(
      "/orders",
      "exceptify.exception_data" => {request_id: "abc"}
    )
    exception = StandardError.new("boom")

    notification = Exceptify::Notification.new(exception, env: env, data: {job: "Import"})

    assert_equal({request_id: "abc", job: "Import"}, notification.data)
    assert_equal env, notification.env
    assert notification.request_context.present?
  end

  test "failure: missing env produces empty request data without raising" do
    notification = Exceptify::Notification.new(StandardError.new("boom"))

    assert_nil notification.env
    assert_equal({}, notification.data)
    assert_empty notification.backtrace
    refute notification.request_context.present?
  end

  test "edge: injected clock hostname and backtrace cleaner are used" do
    exception = StandardError.new("boom")
    exception.set_backtrace(["raw"])
    clock = Struct.new(:current).new(Time.utc(2026, 1, 1))
    cleaner = Object.new
    cleaner.define_singleton_method(:clean_backtrace) { |_exception| ["clean"] }

    notification = Exceptify::Notification.new(
      exception,
      clock: clock,
      hostname: -> { "app-host" },
      backtrace_cleaner: cleaner
    )

    assert_equal Time.utc(2026, 1, 1), notification.timestamp
    assert_equal "app-host", notification.hostname
    assert_equal ["clean"], notification.backtrace
  end
end
