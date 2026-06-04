# frozen_string_literal: true

# -------------------------------------------
# To run the application: ruby examples/sample_app.rb
# -------------------------------------------

require "bundler/inline"

gemfile do
  source "https://rubygems.org"

  gem "rails", "8.0.1"
  gem "exception_notification", path: File.expand_path("../..", __FILE__)
  gem "httparty", "0.22.0"
  gem "mocha", "2.2.0"
end

class SampleApp < Rails::Application
  config.middleware.use ExceptionNotification::Rack,
    webhook: {
      url: "https://example.com"
    }

  config.secret_key_base = "my secret key base"
  config.consider_all_requests_local = true
  config.hosts << "example.org"

  Rails.logger = Logger.new($stdout)

  routes.draw do
    get "/", to: "exceptions#index"
  end
end

require "action_controller/railtie"

class ExceptionsController < ActionController::Base
  def index
    raise "Sample exception raised, you should receive a notification!"
  end
end

require "minitest/autorun"
require "mocha/minitest"

class Test < Minitest::Test
  include Rack::Test::Methods

  def test_raise_exception
    HTTParty.expects(:send).with(:post, "https://example.com", anything)
    get "/"
    assert last_response.server_error?
  end

  private

  def app
    Rails.application
  end
end
