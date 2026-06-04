# frozen_string_literal: true

require "exception_notifier"
require "exceptify/rack"
require "exceptify/version"

module Exceptify
  # Alternative way to setup Exceptify.
  # Run 'rails generate exceptify:install' to create
  # a fresh initializer with all configuration values.
  def self.configure
    yield ExceptionNotifier
  end
end

ExceptionNotification = Exceptify unless defined?(ExceptionNotification)
