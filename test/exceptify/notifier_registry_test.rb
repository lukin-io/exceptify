# frozen_string_literal: true

require "test_helper"

class NotifierRegistryTest < ActiveSupport::TestCase
  test "success: registers callable notifiers" do
    registry = Exceptify::NotifierRegistry.new
    notifier = ->(_exception, _options) {}

    registry.register(:custom, notifier)

    assert_same notifier, registry.fetch(:custom)
    assert_equal [:custom], registry.names
  end

  test "success: builds configured notifier from options" do
    built_notifier = ->(_exception, _options) {}
    registry = Exceptify::NotifierRegistry.new(factory: ->(name, options) {
      assert_equal :email, name
      assert_equal({exception_recipients: ["ops@example.com"]}, options)
      built_notifier
    })

    registry.register(:email, exception_recipients: ["ops@example.com"])

    assert_same built_notifier, registry.fetch(:email)
  end

  test "failure: rejects invalid notifier definitions" do
    registry = Exceptify::NotifierRegistry.new

    error = assert_raises(ArgumentError) do
      registry.register(:broken, "not callable")
    end

    assert_includes error.message, "Invalid notifier"
  end

  test "edge: copies registry without sharing notifier map" do
    registry = Exceptify::NotifierRegistry.new
    registry.register(:one, ->(_exception, _options) {})

    copy = registry.copy
    copy.register(:two, ->(_exception, _options) {})

    assert_equal [:one], registry.names
    assert_equal %i[one two], copy.names
  end
end
