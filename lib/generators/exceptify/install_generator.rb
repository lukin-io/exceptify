# frozen_string_literal: true

module Exceptify
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      desc "Creates an Exceptify initializer."

      source_root File.expand_path("templates", __dir__)
      class_option :resque,
        type: :boolean,
        desc: "Add support for sending notifications when errors occur in Resque jobs."
      class_option :sidekiq,
        type: :boolean,
        desc: "Add support for sending notifications when errors occur in Sidekiq jobs."
      class_option :solid_queue,
        type: :boolean,
        desc: "Add support for sending notifications when errors occur in Solid Queue jobs."

      def copy_initializer
        template "exceptify.rb.erb", "config/initializers/exceptify.rb"
      end
    end
  end
end
