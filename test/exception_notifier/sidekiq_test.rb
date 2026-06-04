# frozen_string_literal: true

require "test_helper"

# To allow sidekiq error handlers to be registered, sidekiq must be in
# "server mode". This mode is triggered by loading sidekiq/cli. Note this
# has to be loaded before exceptify/sidekiq.
require "sidekiq/cli"
require "sidekiq/testing"

require "exceptify/sidekiq"

class MockSidekiqServer
  include ::Sidekiq::Component

  def config
    @config ||= Sidekiq.default_configuration.tap { |config| config.logger = Logger.new(nil) }
  end
end

class SidekiqTest < ActiveSupport::TestCase
  test "should call notify_exception when sidekiq raises an error" do
    server = MockSidekiqServer.new
    message = {}
    exception = RuntimeError.new

    if ::Sidekiq::VERSION < "7.1.5"
      ExceptionNotifier.expects(:notify_exception).with(
        exception,
        data: {sidekiq: message}
      )
    else
      ExceptionNotifier.expects(:notify_exception).with(
        exception,
        data: {sidekiq: {context: message, config: server.config}}
      )
    end

    server.handle_exception(exception, message)
  end
end
