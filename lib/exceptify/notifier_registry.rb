# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module Exceptify
  class NotifierRegistry
    attr_reader :notifiers

    def initialize(notifiers = {}, factory: nil)
      @notifiers = notifiers.dup
      @factory = factory || method(:build_notifier)
    end

    def register(name, notifier_or_options)
      if notifier_or_options.respond_to?(:call)
        notifiers[name] = notifier_or_options
      elsif notifier_or_options.is_a?(Hash)
        notifiers[name] = @factory.call(name, notifier_or_options)
      else
        raise ArgumentError, "Invalid notifier '#{name}' defined as #{notifier_or_options.inspect}"
      end
    end

    def unregister(name)
      notifiers.delete(name)
    end

    def fetch(name)
      notifiers[name]
    end

    def names
      notifiers.keys
    end

    def clear
      notifiers.clear
    end

    def copy
      self.class.new(notifiers, factory: @factory)
    end

    private

    def build_notifier(name, options)
      notifier_classname = "#{name}_notifier".camelize
      notifier_class = Exceptify.const_get(notifier_classname)
      notifier_class.new(options)
    rescue NameError => e
      raise UndefinedNotifierError,
        "No notifier named '#{name}' was found. Please, revise your configuration options. Cause: #{e.message}"
    end
  end
end
