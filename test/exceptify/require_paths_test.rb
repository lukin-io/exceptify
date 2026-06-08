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
      abort "require exceptify should not load Rails" if defined?(Rails)
    RUBY
  end

  test "loads the rack require path" do
    assert_subprocess_success <<~RUBY
      require "exceptify/rack"

      abort "missing Exceptify::Rack" unless Exceptify::Rack
      abort "require exceptify/rack should not load Rails" if defined?(Rails)
    RUBY
  end

  test "loads the solid queue require path" do
    assert_subprocess_success <<~RUBY
      require "exceptify/solid_queue"

      abort "missing Exceptify::SolidQueue" unless Exceptify::SolidQueue
      abort "require exceptify/solid_queue should not load Rails" if defined?(Rails)
    RUBY
  end

  test "loads the version require path" do
    assert_subprocess_success <<~RUBY
      require "exceptify/version"

      abort "missing Exceptify::VERSION" unless Exceptify::VERSION
    RUBY
  end

  private

  def assert_subprocess_success(script)
    stdout, stderr, status = Open3.capture3(RUBY, "-I#{LIB_PATH}", "-e", script)
    assert status.success?, [stdout, stderr].reject(&:empty?).join("\n")
  end
end
