# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  test "success: stores notifier and ignore configuration in a PORO" do
    configuration = Exceptify::Configuration.new
    notifier = ->(_exception, _options) {}

    configuration.add_notifier(:custom, notifier)
    configuration.ignore_if { |_exception, _options| true }

    assert_same notifier, configuration.registered_notifier(:custom)
    assert configuration.ignored?(StandardError.new, {})
  end

  test "failure: ignore condition errors raise in testing mode" do
    configuration = Exceptify::Configuration.new
    configuration.testing_mode!
    configuration.ignore_if { |_exception, _options| raise "bad condition" }

    assert_raises(RuntimeError) do
      configuration.ignored?(StandardError.new, {})
    end
  end

  test "edge: reset clears mutable settings without replacing defaults" do
    configuration = Exceptify::Configuration.new
    configuration.add_notifier(:custom, ->(_exception, _options) {})
    configuration.ignore_if { |_exception, _options| true }
    configuration.error_grouping = true
    configuration.notification_trigger = ->(_exception, _count) { true }

    configuration.reset!

    assert_empty configuration.notifiers
    refute configuration.error_grouping
    assert_nil configuration.notification_trigger
    assert_equal Exceptify::Configuration::DEFAULT_IGNORED_EXCEPTIONS, configuration.ignored_exceptions
    refute configuration.ignored?(StandardError.new, {})
  end

  test "edge: copy does not share mutable registry or ignore arrays" do
    configuration = Exceptify::Configuration.new
    configuration.add_notifier(:one, ->(_exception, _options) {})
    configuration.ignore_if { |_exception, _options| false }

    copy = configuration.copy
    copy.add_notifier(:two, ->(_exception, _options) {})
    copy.ignore_if { |_exception, _options| true }

    assert_equal [:one], configuration.notifiers
    assert_equal %i[one two], copy.notifiers
    refute configuration.ignored?(StandardError.new, {})
    assert copy.ignored?(StandardError.new, {})
  end
end
