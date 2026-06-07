# frozen_string_literal: true

# Reset global test configuration between examples to avoid order-dependent failures.
module Exceptify
  def self.reset_notifiers!
    reset!
    testing_mode!
  end
end
