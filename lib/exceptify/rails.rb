# frozen_string_literal: true

# Warning: This must be required after rails but before initializers have been run. If you require
# it from config/initializers/exceptify.rb, then the rails and rake_task callbacks
# registered here will have no effect, because Rails will have already invoked all registered rails
# and rake_tasks handlers.

require "exceptify"

module Exceptify
  class Engine < ::Rails::Engine
    config.exceptify = Exceptify
    config.exceptify.logger = Rails.logger
    config.exceptify.error_grouping_cache = Rails.cache

    config.app_middleware.use Exceptify::Rack

    rake_tasks do
      # Report exceptions occurring in Rake tasks.
      require "exceptify/rake"
    end

    runner do
      # Report exceptions occurring in runner commands.
      require "exceptify/rails/runner_tie"
      Exceptify::Rails::RunnerTie.new.call
    end
  end
end
