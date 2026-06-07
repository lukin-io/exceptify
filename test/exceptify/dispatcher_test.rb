# frozen_string_literal: true

require "test_helper"

class DispatcherTest < ActiveSupport::TestCase
  test "success: dispatches to selected registered notifiers" do
    configuration = Exceptify::Configuration.new
    calls = []
    configuration.add_notifier(:one, ->(_exception, _options) { calls << :one })
    configuration.add_notifier(:two, ->(_exception, _options) { calls << :two })

    result = Exceptify::Dispatcher.new(configuration).notify_exception(StandardError.new, notifiers: :two)

    assert result
    assert_equal [:two], calls
  end

  test "failure: returns false when notification is ignored" do
    configuration = Exceptify::Configuration.new
    configuration.add_notifier(:one, ->(_exception, _options) { flunk "should not notify" })
    configuration.ignore_if { |_exception, _options| true }

    refute Exceptify::Dispatcher.new(configuration).notify_exception(StandardError.new)
  end

  test "failure: re-raises notifier errors in testing mode" do
    configuration = Exceptify::Configuration.new
    configuration.testing_mode!
    configuration.add_notifier(:broken, ->(_exception, _options) { raise "delivery failed" })

    assert_raises(RuntimeError) do
      Exceptify::Dispatcher.new(configuration).notify_exception(StandardError.new)
    end
  end

  test "edge: returns false when all selected notifiers are filtered" do
    configuration = Exceptify::Configuration.new
    configuration.add_notifier(:one, ->(_exception, _options) { flunk "should not notify" })
    configuration.ignore_notifier_if(:one) { |_exception, _options| true }

    refute Exceptify::Dispatcher.new(configuration).notify_exception(StandardError.new)
  end

  test "edge: does not mutate caller options" do
    configuration = Exceptify::Configuration.new
    configuration.add_notifier(:one, ->(_exception, _options) {})
    options = {notifiers: :one, data: {id: 1}}

    Exceptify::Dispatcher.new(configuration).notify_exception(StandardError.new, options)

    assert_equal({notifiers: :one, data: {id: 1}}, options)
  end
end
