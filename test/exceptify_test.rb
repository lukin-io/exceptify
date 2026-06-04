# frozen_string_literal: true

require "test_helper"

class ExceptionOne < StandardError; end

class ExceptionTwo < StandardError; end

class StandardErrorSubclass < StandardError; end

class ExceptifyTest < ActiveSupport::TestCase
  setup do
    Exceptify.register_notifier(:email, exception_recipients: %w[dummyexceptions@example.com])

    @notifier_calls = 0
    @test_notifier = ->(_exception, _options) { @notifier_calls += 1 }
  end

  teardown do
    Exceptify.reset_notifiers!

    Rails.cache.clear if defined?(Rails) && Rails.respond_to?(:cache)
  end

  test "should have default ignored exceptions" do
    assert_equal Exceptify.ignored_exceptions,
      ["ActiveRecord::RecordNotFound", "Mongoid::Errors::DocumentNotFound",
        "AbstractController::ActionNotFound", "ActionController::RoutingError",
        "ActionController::UnknownFormat", "ActionController::UrlGenerationError",
        "ActionDispatch::Http::MimeNegotiation::InvalidType",
        "Rack::Utils::InvalidParameterError"]
  end

  test "should have email notifier registered" do
    assert_equal Exceptify.notifiers, [:email]
  end

  test "should have a valid email notifier" do
    @email_notifier = Exceptify.registered_notifier(:email)
    refute_nil @email_notifier
    assert_equal @email_notifier.class, Exceptify::EmailNotifier
    assert_respond_to @email_notifier, :call
  end

  test "should allow register/unregister another notifier" do
    called = false
    proc_notifier = ->(_exception, _options) { called = true }
    Exceptify.register_notifier(:proc, proc_notifier)

    assert_equal Exceptify.notifiers.sort, %i[email proc]

    exception = StandardError.new

    Exceptify.notify_exception(exception)
    assert called

    Exceptify.unregister_notifier(:proc)
    assert_equal Exceptify.notifiers, [:email]
  end

  test "should allow select notifiers to send error to" do
    notifier1_calls = 0
    notifier1 = ->(_exception, _options) { notifier1_calls += 1 }
    Exceptify.register_notifier(:notifier1, notifier1)

    notifier2_calls = 0
    notifier2 = ->(_exception, _options) { notifier2_calls += 1 }
    Exceptify.register_notifier(:notifier2, notifier2)

    assert_equal Exceptify.notifiers.sort, %i[email notifier1 notifier2]

    exception = StandardError.new
    Exceptify.notify_exception(exception)
    assert_equal notifier1_calls, 1
    assert_equal notifier2_calls, 1

    Exceptify.notify_exception(exception, notifiers: :notifier1)
    assert_equal notifier1_calls, 2
    assert_equal notifier2_calls, 1

    Exceptify.notify_exception(exception, notifiers: :notifier2)
    assert_equal notifier1_calls, 2
    assert_equal notifier2_calls, 2

    Exceptify.unregister_notifier(:notifier1)
    Exceptify.unregister_notifier(:notifier2)
    assert_equal Exceptify.notifiers, [:email]
  end

  test "should ignore exception if satisfies conditional ignore" do
    env = "production"
    Exceptify.ignore_if do |_exception, _options|
      env != "production"
    end

    Exceptify.register_notifier(:test, @test_notifier)

    exception = StandardError.new

    Exceptify.notify_exception(exception, notifiers: :test)
    assert_equal @notifier_calls, 1

    env = "development"
    Exceptify.notify_exception(exception, notifiers: :test)
    assert_equal @notifier_calls, 1
  end

  test "should ignore exception if satisfies by-notifier conditional ignore" do
    notifier1_calls = 0
    notifier1 = ->(_exception, _options) { notifier1_calls += 1 }
    Exceptify.register_notifier(:notifier1, notifier1)

    notifier2_calls = 0
    notifier2 = ->(_exception, _options) { notifier2_calls += 1 }
    Exceptify.register_notifier(:notifier2, notifier2)

    env = "production"
    Exceptify.ignore_notifier_if(:notifier1) do |_exception, _options|
      env == "development"
    end
    Exceptify.ignore_notifier_if(:notifier2) do |_exception, _options|
      env == "production"
    end

    exception = StandardError.new

    Exceptify.notify_exception(exception)
    assert_equal notifier1_calls, 1
    assert_equal notifier2_calls, 0

    env = "development"

    Exceptify.notify_exception(exception)
    assert_equal notifier1_calls, 1
    assert_equal notifier2_calls, 1

    env = "test"

    Exceptify.notify_exception(exception)
    assert_equal notifier1_calls, 2
    assert_equal notifier2_calls, 2
  end

  test "should return false if all the registered notifiers are ignored" do
    Exceptify.notifiers.each do |notifier|
      # make sure to register no other notifiers but the tested ones
      Exceptify.unregister_notifier(notifier)
    end

    Exceptify.register_notifier(:notifier1, ->(_, _) {})
    Exceptify.register_notifier(:notifier2, ->(_, _) {})

    Exceptify.ignore_notifier_if(:notifier1) do |exception, _options|
      exception.message =~ /non_critical_error/
    end
    Exceptify.ignore_notifier_if(:notifier2) do |exception, _options|
      exception.message =~ /non_critical_error/
    end

    exception = StandardError.new("a non_critical_error occured.")

    refute Exceptify.notify_exception(exception)
  end

  test "should return true if one of the notifiers fires" do
    Exceptify.notifiers.each do |notifier|
      # make sure to register no other notifiers but the tested ones
      Exceptify.unregister_notifier(notifier)
    end

    Exceptify.register_notifier(:notifier1, ->(_, _) {})
    Exceptify.register_notifier(:notifier2, ->(_, _) {})

    Exceptify.ignore_notifier_if(:notifier1) do |exception, _options|
      exception.message =~ /non-critical\serror/
    end

    exception = StandardError.new("a non-critical error occured")

    assert Exceptify.notify_exception(exception)
  end

  test "should not send notification if one of ignored exceptions" do
    Exceptify.register_notifier(:test, @test_notifier)

    exception = StandardError.new

    Exceptify.notify_exception(exception, notifiers: :test)
    assert_equal @notifier_calls, 1

    Exceptify.notify_exception(exception, notifiers: :test, ignore_exceptions: "StandardError")
    assert_equal @notifier_calls, 1
  end

  test "should not send notification if subclass of one of ignored exceptions" do
    Exceptify.register_notifier(:test, @test_notifier)

    exception = StandardErrorSubclass.new

    Exceptify.notify_exception(exception, notifiers: :test)
    assert_equal @notifier_calls, 1

    Exceptify.notify_exception(exception, notifiers: :test, ignore_exceptions: "StandardError")
    assert_equal @notifier_calls, 1
  end

  test "should not send notification if extended module one of ignored exceptions" do
    Exceptify.register_notifier(:test, @test_notifier)

    # Define module at runtime
    Object.const_set(:StandardErrorModule, Module.new)

    exception = StandardError.new
    exception.extend StandardErrorModule

    Exceptify.notify_exception(exception, notifiers: :test)
    assert_equal @notifier_calls, 1

    ignore_exceptions = "StandardErrorModule"
    Exceptify.notify_exception(exception, notifiers: :test, ignore_exceptions: ignore_exceptions)
    assert_equal @notifier_calls, 1
  ensure
    # Clean up by removing the module
    Object.send(:remove_const, :StandardErrorModule)
  end

  test "should not send notification if prepended module at singleton class one of ignored exceptions" do
    Exceptify.register_notifier(:test, @test_notifier)

    # Define module at runtime
    Object.const_set(:StandardErrorModule, Module.new)

    exception = StandardError.new
    exception.singleton_class.prepend StandardErrorModule

    Exceptify.notify_exception(exception, notifiers: :test)
    assert_equal @notifier_calls, 1

    ignore_exceptions = "StandardErrorModule"
    Exceptify.notify_exception(exception, notifiers: :test, ignore_exceptions: ignore_exceptions)
    assert_equal @notifier_calls, 1
  ensure
    # Clean up by removing the module
    Object.send(:remove_const, :StandardErrorModule)
  end

  test "should call received block" do
    @block_called = false
    notifier = ->(_exception, _options, &block) { block.call }
    Exceptify.register_notifier(:test, notifier)

    exception = ExceptionOne.new

    Exceptify.notify_exception(exception) do
      @block_called = true
    end

    assert @block_called
  end

  test "should not call group_error! or send_notification? if error_grouping false" do
    exception = StandardError.new
    Exceptify.expects(:group_error!).never
    Exceptify.expects(:send_notification?).never

    Exceptify.notify_exception(exception)
  end

  test "should call group_error! and send_notification? if error_grouping true" do
    Exceptify.error_grouping = true

    exception = StandardError.new
    Exceptify.expects(:group_error!).once
    Exceptify.expects(:send_notification?).once

    Exceptify.notify_exception(exception)
  end

  test "should skip notification if send_notification? is false" do
    Exceptify.error_grouping = true

    exception = StandardError.new
    Exceptify.expects(:group_error!).once.returns(1)
    Exceptify.expects(:send_notification?).with(exception, 1).once.returns(false)

    refute Exceptify.notify_exception(exception)
  end

  test "should send notification if send_notification? is true" do
    Exceptify.error_grouping = true

    exception = StandardError.new
    Exceptify.expects(:group_error!).once.returns(1)
    Exceptify.expects(:send_notification?).with(exception, 1).once.returns(true)

    assert Exceptify.notify_exception(exception)
  end
end
