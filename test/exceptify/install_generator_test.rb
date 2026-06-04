# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/exceptify/install_generator"

class ExceptifyInstallGeneratorTest < Rails::Generators::TestCase
  tests Exceptify::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generators", __dir__)

  setup :prepare_destination

  test "creates the exceptify initializer" do
    run_generator

    assert_file "config/initializers/exceptify.rb" do |initializer|
      assert_match 'require "exceptify/rails"', initializer
      assert_match 'require "exceptify/rake"', initializer
      assert_match "Exceptify.configure do |config|", initializer
      assert_match "config.add_notifier :email", initializer
    end
  end

  test "adds sidekiq support when requested" do
    run_generator ["--sidekiq"]

    assert_file "config/initializers/exceptify.rb" do |initializer|
      assert_match 'require "exceptify/sidekiq"', initializer
    end
  end

  test "adds resque support when requested" do
    run_generator ["--resque"]

    assert_file "config/initializers/exceptify.rb" do |initializer|
      assert_match 'require "exceptify/resque"', initializer
      assert_match "Resque::Failure.backend = Resque::Failure::Multiple", initializer
    end
  end
end
