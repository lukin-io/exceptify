# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class ExceptifyRequirePathsTest < ActiveSupport::TestCase
  RUBY = RbConfig.ruby
  LIB_PATH = File.expand_path("../../lib", __dir__)

  test "loads the preferred exceptify require path" do
    assert_subprocess_success <<~RUBY
      require "exceptify"

      abort "missing Exceptify::VERSION" unless Exceptify::VERSION
      abort "missing Exceptify::Rack" unless Exceptify::Rack
      abort "missing compatibility alias" unless ExceptionNotification == Exceptify
    RUBY
  end

  test "keeps the old exception_notification require path compatible" do
    assert_subprocess_success <<~RUBY
      require "exception_notification"

      abort "missing old namespace" unless ExceptionNotification::VERSION
      abort "missing old rack constant" unless ExceptionNotification::Rack
      abort "missing new namespace" unless Exceptify::VERSION
      abort "namespaces differ" unless ExceptionNotification == Exceptify
    RUBY
  end

  test "keeps old nested require paths compatible" do
    assert_subprocess_success <<~RUBY
      require "exception_notification/rack"
      require "exception_notification/version"

      abort "missing old rack constant" unless ExceptionNotification::Rack
      abort "missing new rack constant" unless Exceptify::Rack
      abort "missing old version constant" unless ExceptionNotification::VERSION
    RUBY
  end

  private

  def assert_subprocess_success(script)
    stdout, stderr, status = Open3.capture3(RUBY, "-I#{LIB_PATH}", "-e", script)
    assert status.success?, [stdout, stderr].reject(&:empty?).join("\n")
  end
end
