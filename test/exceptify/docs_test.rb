# frozen_string_literal: true

require "test_helper"

class DocsTest < ActiveSupport::TestCase
  NOTIFIER_DOCS = {
    email: "docs/notifiers/email.md",
    slack: "docs/notifiers/slack.md",
    teams: "docs/notifiers/teams.md",
    sns: "docs/notifiers/sns.md",
    datadog: "docs/notifiers/datadog.md",
    webhook: "docs/notifiers/webhook.md"
  }.freeze

  CUSTOM_DOC = "docs/notifiers/custom.md"
  ROOT = File.expand_path("../..", __dir__)

  test "success: documented notifiers have docs and implementation" do
    NOTIFIER_DOCS.each do |name, doc_path|
      assert_file doc_path
      assert_file "lib/exceptify/#{name}_notifier.rb"
    end
  end

  test "edge: custom notifier docs are exempt from implementation file requirement" do
    assert_file CUSTOM_DOC
    refute_file "lib/exceptify/custom_notifier.rb"
  end

  test "edge: notifier docs and implementation files only include supported built ins" do
    expected_docs = NOTIFIER_DOCS.values.sort
    actual_docs = Dir.glob(File.join(ROOT, "docs/notifiers/*.md"))
      .map { |path| path.delete_prefix("#{ROOT}/") }
      .reject { |path| path == CUSTOM_DOC }
      .sort

    expected_implementations = NOTIFIER_DOCS.keys.map { |name| "lib/exceptify/#{name}_notifier.rb" }.sort
    actual_implementations = Dir.glob(File.join(ROOT, "lib/exceptify/*_notifier.rb"))
      .map { |path| path.delete_prefix("#{ROOT}/") }
      .reject { |path| path == "lib/exceptify/base_notifier.rb" }
      .sort

    assert_equal expected_docs, actual_docs
    assert_equal expected_implementations, actual_implementations
  end

  private

  def assert_file(path)
    assert File.file?(File.join(ROOT, path)), "Expected #{path} to exist"
  end

  def refute_file(path)
    refute File.exist?(File.join(ROOT, path)), "Expected #{path} to be absent"
  end
end
