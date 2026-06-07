# frozen_string_literal: true

require "test_helper"

require "rake"
require "exceptify/rake"

class RakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task.clear
    Rake::Task.define_task :dependency_1 do
      nil # noop but could puts for debugging
    end
    Rake::Task.define_task raise_exception: :dependency_1 do
      raise "test exception"
    end
    @task = Rake::Task[:raise_exception]
  end

  teardown do
    Rake::Task.clear
  end

  test "notifies of exception" do
    Exceptify.expects(:notify_exception).with do |ex, opts|
      data = opts[:data]
      ex.is_a?(RuntimeError) &&
        ex.message == "test exception" &&
        data[:error_class] == "RuntimeError" &&
        data[:error_message] == "test exception" &&
        data[:rake][:rake_command_line] == "rake " &&
        data[:rake][:name] == "raise_exception" &&
        data[:rake][:timestamp] &&
        data[:rake][:sources] == ["dependency_1"] &&
        data[:rake][:prerequisite_tasks][0][:name] == "dependency_1"
    end

    # The original error is re-raised
    assert_raises(RuntimeError) do
      @task.invoke
    end
  end

  test "does not notify when task succeeds" do
    Rake::Task.define_task :successful_task do
      "ok"
    end

    Exceptify.expects(:notify_exception).never

    Rake::Task[:successful_task].invoke
  end

  test "does not notify for system exit" do
    Rake::Task.define_task :system_exit do
      raise SystemExit.new(1)
    end

    Exceptify.expects(:notify_exception).never

    assert_raises(SystemExit) do
      Rake::Task[:system_exit].invoke
    end
  end
end
