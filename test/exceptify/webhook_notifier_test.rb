# frozen_string_literal: true

require "test_helper"
require "httparty"

class WebhookNotifierTest < ActiveSupport::TestCase
  test "should send webhook notification with request payload if env is present" do
    url = "http://localhost:8000"
    http_client = FakeWebhookHTTPClient.new
    webhook = Exceptify::WebhookNotifier.new(url: url, http_client: http_client)

    webhook.call(fake_exception, env: webhook_env)

    method, request_url, params = http_client.requests.first
    assert_equal :post, method
    assert_equal url, request_url

    body = params[:body]
    assert_equal Socket.gethostname, body[:server]
    assert_equal Process.pid, body[:process]
    assert_equal "ZeroDivisionError", body[:exception][:error_class]
    assert_includes body[:exception][:message], "divided by 0"
    assert_includes body[:exception][:backtrace].first, "webhook_notifier_test.rb"
    assert_equal({account_id: 7}, body[:data])
    assert_equal "http://example.com/example?id=foo&secret=secret", body[:request][:url]
    assert_equal "GET", body[:request][:http_method]
    assert_equal "192.168.1.1", body[:request][:ip_address]
    assert_equal({"id" => "foo", "secret" => "[FILTERED]"}, body[:request][:parameters])
    assert_equal({"session_id" => "session-1"}, body[:session])
    assert_equal "example.com", body[:environment]["HTTP_HOST"]
  end

  test "should send webhook notification with correct params data" do
    url = "http://localhost:8000"
    fake_exception.stubs(:backtrace).returns("the backtrace")
    webhook = Exceptify::WebhookNotifier.new(url: url)

    HTTParty.expects(:send).with(:post, url, fake_params)

    webhook.call(fake_exception)
  end

  test "success: uses injected http client" do
    url = "http://localhost:8000"
    fake_exception.stubs(:backtrace).returns("the backtrace")
    http_client = FakeWebhookHTTPClient.new
    webhook = Exceptify::WebhookNotifier.new(url: url, http_client: http_client)

    webhook.call(fake_exception)

    assert_equal [:post, url, fake_params], http_client.requests.first
  end

  test "failure: raises if webhook url is missing" do
    webhook = Exceptify::WebhookNotifier.new({})

    error = assert_raises ArgumentError do
      webhook.call(fake_exception)
    end

    assert_equal "You must provide 'url' option", error.message
  end

  test "edge: raises if webhook url is blank" do
    webhook = Exceptify::WebhookNotifier.new(url: "")

    error = assert_raises ArgumentError do
      webhook.call(fake_exception)
    end

    assert_equal "You must provide 'url' option", error.message
  end

  test "should call pre/post_callback if specified" do
    pre_callback_called = 0
    post_callback_called = 0

    HTTParty.expects(:send).returns(fake_response)
    webhook = Exceptify::WebhookNotifier.new(
      url: "http://localhost:8000",
      pre_callback: proc { |*| pre_callback_called += 1 },
      post_callback: proc { |*| post_callback_called += 1 }
    )
    webhook.call(fake_exception)

    assert_equal 1, pre_callback_called
    assert_equal 1, post_callback_called
  end

  private

  def fake_response
    {
      status: 200,
      body: {
        exception: {
          error_class: "ZeroDivisionError",
          message: "divided by 0",
          backtrace: "/exceptify/test/webhook_notifier_test.rb:48:in `/"
        },
        data: {
          extra_data: {data_item1: "datavalue1", data_item2: "datavalue2"}
        },
        request: {
          cookies: {cookie_item1: "cookieitemvalue1", cookie_item2: "cookieitemvalue2"},
          url: "http://example.com/example",
          ip_address: "192.168.1.1",
          environment: {env_item1: "envitem1", env_item2: "envitem2"},
          controller: "#<ControllerName:0x007f9642a04d00>",
          session: {session_item1: "sessionitem1", session_item2: "sessionitem2"},
          parameters: {action: "index", controller: "projects"}
        }
      }
    }
  end

  def fake_params
    params = {
      body: {
        server: Socket.gethostname,
        process: Process.pid,
        exception: {
          error_class: "ZeroDivisionError",
          message: "divided by 0".inspect,
          backtrace: "the backtrace"
        },
        data: {}
      }
    }

    params[:body][:rails_root] = Rails.root if defined?(::Rails) && Rails.respond_to?(:root)

    params
  end

  def webhook_env
    Rack::MockRequest.env_for(
      "/example",
      "HTTP_HOST" => "example.com",
      "REMOTE_ADDR" => "192.168.1.1",
      "HTTP_USER_AGENT" => "Rails Testing",
      "action_dispatch.parameter_filter" => ["secret"],
      "rack.session" => {"session_id" => "session-1"},
      "rack.session.options" => {},
      "exceptify.exception_data" => {account_id: 7},
      :params => {id: "foo", secret: "secret"}
    )
  end

  def fake_exception
    @fake_exception ||= begin
      5 / 0
    rescue => e
      e
    end
  end
end

class FakeWebhookHTTPClient
  attr_reader :requests

  def initialize
    @requests = []
  end

  def send(method, url, options)
    @requests << [method, url, options]
  end
end
