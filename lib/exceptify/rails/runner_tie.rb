# frozen_string_literal: true

require "exceptify"

module Exceptify
  module Rails
    class RunnerTie
      class << self
        attr_writer :installed

        def installed?
          @installed == true
        end

        def reset!
          @installed = false
        end
      end

      def initialize(registrar: nil, error_source: nil, notifier: Exceptify)
        @registrar = registrar || ->(&block) { at_exit(&block) }
        @error_source = error_source || -> { $ERROR_INFO }
        @notifier = notifier
      end

      # Registers an at_exit callback, which checks if there was an exception. This is a pretty
      # crude way to detect exceptions from runner commands, but Rails doesn't provide a better API.
      #
      # This should only be called from a runner callback in your Rails config; otherwise you may
      # register the at_exit callback in more places than you need or want it.
      def call
        return false if self.class.installed?

        self.class.installed = true

        @registrar.call do
          exception = @error_source.call
          if exception && !exception.is_a?(SystemExit)
            @notifier.notify_exception(exception, data: data_for_exceptify(exception))
          end
        end

        true
      end

      private

      def data_for_exceptify(exception = nil)
        data = {}
        data[:error_class] = exception.class.name if exception
        data[:error_message] = exception.message if exception

        data
      end
    end
  end
end
