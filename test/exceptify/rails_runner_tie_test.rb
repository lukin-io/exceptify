# frozen_string_literal: true

require "test_helper"
require "exceptify/rails/runner_tie"

class RailsRunnerTieTest < ActiveSupport::TestCase
  setup do
    Exceptify::Rails::RunnerTie.reset!
  end

  teardown do
    Exceptify::Rails::RunnerTie.reset!
  end

  test "success: notifies runner exception when exit hook runs" do
    blocks = []
    exception = RuntimeError.new("runner failed")
    notifier = mock("notifier")
    notifier.expects(:notify_exception).with(
      exception,
      data: {
        error_class: "RuntimeError",
        error_message: "runner failed"
      }
    )

    tie = Exceptify::Rails::RunnerTie.new(
      registrar: ->(&block) { blocks << block },
      error_source: -> { exception },
      notifier: notifier
    )

    assert_equal true, tie.call
    blocks.first.call
  end

  test "failure: does not notify system exit" do
    blocks = []
    notifier = mock("notifier")
    notifier.expects(:notify_exception).never

    tie = Exceptify::Rails::RunnerTie.new(
      registrar: ->(&block) { blocks << block },
      error_source: -> { SystemExit.new(1) },
      notifier: notifier
    )

    assert_equal true, tie.call
    blocks.first.call
  end

  test "edge: duplicate installation registers one exit hook" do
    blocks = []
    tie = Exceptify::Rails::RunnerTie.new(
      registrar: ->(&block) { blocks << block }
    )

    assert_equal true, tie.call
    assert_equal false, tie.call
    assert_equal 1, blocks.size
  end
end
