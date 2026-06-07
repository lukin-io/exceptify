# frozen_string_literal: true

require "action_dispatch"

module Exceptify
  class RequestContext
    attr_reader :env

    def initialize(env)
      @env = env
    end

    def present?
      !env.nil?
    end

    def request
      @request ||= ActionDispatch::Request.new(env) if present?
    end

    def controller
      env["action_controller.instance"] if present?
    end

    def controller_and_action
      "#{controller.controller_name}##{controller.action_name}" if controller
    end

    def exception_data
      return {} unless present?

      env["exceptify.exception_data"] || {}
    end
  end
end
