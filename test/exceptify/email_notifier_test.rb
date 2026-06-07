# frozen_string_literal: true

require "test_helper"
require "action_mailer"
require "action_controller"

class EmailNotifierTest < ActiveSupport::TestCase
  setup do
    Time.stubs(:current).returns("Sat, 20 Apr 2013 20:58:55 UTC +00:00")
    ActionMailer::Base.deliveries.clear

    @exception = ZeroDivisionError.new("divided by 0")
    @exception.set_backtrace(["test/exceptify/email_notifier_test.rb:20"])

    @email_notifier = Exceptify::EmailNotifier.new(
      email_prefix: "[Dummy ERROR] ",
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      email_headers: {"X-Custom-Header" => "foobar"},
      sections: %w[new_section request session environment backtrace],
      background_sections: %w[new_bkg_section backtrace data],
      pre_callback: proc { |_opts, _notifier, _backtrace, _message, _message_opts| @pre_callback_called = true },
      post_callback: proc { |_opts, _notifier, _backtrace, _message, _message_opts| @post_callback_called = true },
      smtp_settings: {
        user_name: "Dummy user_name",
        password: "Dummy password"
      }
    )

    @mail = @email_notifier.create_email(
      @exception,
      data: {job: "DivideWorkerJob", payload: "1/0", message: "My Custom Message"}
    )
  end

  test "should call pre/post_callback if specified" do
    assert @pre_callback_called
    assert @post_callback_called
  end

  test "create_email builds background email without delivery" do
    assert_empty ActionMailer::Base.deliveries
    assert_respond_to @mail, :deliver_now
  end

  test "sends mail with correct content" do
    assert_equal %("Dummy Notifier" <dummynotifier@example.com>), @mail[:from].value
    assert_equal %w[dummyexceptions@example.com], @mail.to
    assert_equal '[Dummy ERROR]  (ZeroDivisionError) "divided by 0"', @mail.subject
    assert_equal "foobar", @mail["X-Custom-Header"].value
    assert_equal "text/plain; charset=UTF-8", @mail.content_type
    assert_equal [], @mail.attachments
    assert_equal "Dummy user_name", @mail.delivery_method.settings[:user_name]
    assert_equal "Dummy password", @mail.delivery_method.settings[:password]

    # standard:disable Lint/LiteralInInterpolation
    body = <<~BODY
      A ZeroDivisionError occurred in background at Sat, 20 Apr 2013 20:58:55 UTC +00:00 :

        divided by 0
        test/exceptify/email_notifier_test.rb:20

      -------------------------------
      New bkg section:
      -------------------------------

        * New background section for testing

      -------------------------------
      Backtrace:
      -------------------------------

        test/exceptify/email_notifier_test.rb:20

      -------------------------------
      Data:
      -------------------------------

        * data: #{{job: "DivideWorkerJob", payload: "1/0", message: "My Custom Message"}}


    BODY
    # standard:enable Lint/LiteralInInterpolation

    assert_equal body, @mail.decode_body
  end

  test "should normalize multiple digits into one N" do
    assert_equal "N foo N bar N baz N",
      Exceptify::EmailNotifier.normalize_digits("1 foo 12 bar 123 baz 1234")
  end

  test "mail should prefix exception class with 'an' instead of 'a' when it starts with a vowel" do
    begin
      raise ArgumentError
    rescue => e
      @vowel_exception = e
      @vowel_mail = @email_notifier.create_email(@vowel_exception)
    end

    assert_empty ActionMailer::Base.deliveries
    assert_includes @vowel_mail.encoded, "An ArgumentError occurred in background at #{Time.current}"
  end

  test "should not send notification if one of ignored exceptions" do
    begin
      raise AbstractController::ActionNotFound
    rescue => e
      @ignored_exception = e
      unless Exceptify.ignored_exceptions.include?(@ignored_exception.class.name)
        ignored_mail = @email_notifier.create_email(@ignored_exception)
      end
    end

    assert_equal @ignored_exception.class.inspect, "AbstractController::ActionNotFound"
    assert_nil ignored_mail
  end

  test "should encode environment strings" do
    email_notifier = Exceptify::EmailNotifier.new(
      sender_address: "<dummynotifier@example.com>",
      exception_recipients: %w[dummyexceptions@example.com]
    )

    mail = email_notifier.create_email(
      @exception,
      env: {
        "REQUEST_METHOD" => "GET",
        "rack.input" => "",
        "invalid_encoding" => "R\xC3\xA9sum\xC3\xA9".dup.force_encoding(Encoding::ASCII)
      }
    )

    assert_empty ActionMailer::Base.deliveries
    assert_match(/invalid_encoding\s+: R__sum__/, mail.encoded)
  end

  test "should send email using ActionMailer" do
    ActionMailer::Base.deliveries.clear
    @email_notifier.call(@exception)
    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  test "should be able to specify ActionMailer::MessageDelivery method" do
    ActionMailer::Base.deliveries.clear

    deliver_with = if ActionMailer.version < Gem::Version.new("4.2")
      :deliver
    else
      :deliver_now
    end

    email_notifier = Exceptify::EmailNotifier.new(
      email_prefix: "[Dummy ERROR] ",
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      deliver_with: deliver_with
    )

    email_notifier.call(@exception)

    assert_equal 1, ActionMailer::Base.deliveries.count
  end

  test "should lazily evaluate exception_recipients" do
    exception_recipients = %w[first@example.com second@example.com]
    email_notifier = Exceptify::EmailNotifier.new(
      email_prefix: "[Dummy ERROR] ",
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: -> { [exception_recipients.shift] },
      delivery_method: :test
    )

    mail = email_notifier.create_email(@exception)
    assert_equal %w[first@example.com], mail.to
    mail = email_notifier.create_email(@exception)
    assert_equal %w[second@example.com], mail.to
    assert_empty ActionMailer::Base.deliveries
  end

  test "should prepend accumulated_errors_count in email subject if accumulated_errors_count larger than 1" do
    email_notifier = Exceptify::EmailNotifier.new(
      email_prefix: "[Dummy ERROR] ",
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      delivery_method: :test
    )

    mail = email_notifier.create_email(@exception, accumulated_errors_count: 3)
    assert_empty ActionMailer::Base.deliveries
    assert mail.subject.start_with?("[Dummy ERROR] (3 times) (ZeroDivisionError)")
  end

  test "should not include exception message in subject when verbose_subject: false" do
    email_notifier = Exceptify::EmailNotifier.new(
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      verbose_subject: false
    )

    mail = email_notifier.create_email(@exception)

    assert_empty ActionMailer::Base.deliveries
    assert_equal "[ERROR]  (ZeroDivisionError)", mail.subject
  end

  test "should send html email when selected html format" do
    email_notifier = Exceptify::EmailNotifier.new(
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      email_format: :html
    )

    mail = email_notifier.create_email(@exception)

    assert_empty ActionMailer::Base.deliveries
    assert mail.multipart?
  end
end

class EmailNotifierSubjectTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "normalizes digits in subject without delivery" do
    exception = RuntimeError.new("User 123 failed at line 456")
    notifier = build_notifier(normalize_subject: true)

    mail = notifier.create_email(exception)

    assert_equal '[ERROR]  (RuntimeError) "User N failed at line N"', mail.subject
    assert_empty ActionMailer::Base.deliveries
  end

  test "truncates long subject without delivery" do
    exception = RuntimeError.new("x" * 200)
    notifier = build_notifier

    mail = notifier.create_email(exception)

    assert_equal 123, mail.subject.length
    assert mail.subject.end_with?("...")
    assert_empty ActionMailer::Base.deliveries
  end

  test "uses env options when building request email subject" do
    exception = RuntimeError.new("failed")
    env = request_env.merge("exceptify.options" => {email_prefix: "[ENV] "})
    notifier = build_notifier

    mail = notifier.create_email(exception, env: env)

    assert_equal '[ENV] home#index (RuntimeError) "failed"', mail.subject
    assert_empty ActionMailer::Base.deliveries
  end

  private

  def build_notifier(options = {})
    Exceptify::EmailNotifier.new({
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com]
    }.merge(options))
  end

  def request_env
    Rack::MockRequest.env_for(
      "/",
      "action_controller.instance" => controller,
      "rack.session.options" => {}
    )
  end

  def controller
    @controller ||= begin
      controller = EmailNotifierWithEnvTest::HomeController.new
      controller.process(:index)
      controller
    end
  end
end

class EmailNotifierPayloadTest < ActiveSupport::TestCase
  setup do
    Time.stubs(:current).returns("Sat, 20 Apr 2013 20:58:55 UTC +00:00")
    ActionMailer::Base.deliveries.clear
  end

  test "merges request exception data and explicit data without delivery" do
    exception = RuntimeError.new("failed")
    exception.set_backtrace(["app/jobs/import.rb:10"])
    env = request_env.merge(
      "exceptify.exception_data" => {account_id: 7}
    )
    notifier = Exceptify::EmailNotifier.new(
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      sections: []
    )

    mail = notifier.create_email(exception, env: env, data: {job: "Import"})

    assert_includes mail.decode_body, '* data: {account_id: 7, job: "Import"}'
    assert_empty ActionMailer::Base.deliveries
  end

  test "does not add data section when request and explicit data are empty" do
    exception = RuntimeError.new("failed")
    notifier = Exceptify::EmailNotifier.new(
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      background_sections: %w[backtrace]
    )

    mail = notifier.create_email(exception)

    refute_includes mail.decode_body, "Data:"
    assert_empty ActionMailer::Base.deliveries
  end

  private

  def request_env
    Rack::MockRequest.env_for(
      "/",
      "action_controller.instance" => controller,
      "rack.session.options" => {}
    )
  end

  def controller
    @controller ||= begin
      controller = EmailNotifierWithEnvTest::HomeController.new
      controller.process(:index)
      controller
    end
  end
end

class EmailNotifierWithEnvTest < ActiveSupport::TestCase
  class HomeController < ActionController::Metal
    def index
    end
  end

  setup do
    Time.stubs(:current).returns("Sat, 20 Apr 2013 20:58:55 UTC +00:00")
    ActionMailer::Base.deliveries.clear

    @exception = ZeroDivisionError.new("divided by 0")
    @exception.set_backtrace(["test/exceptify/email_notifier_test.rb:20"])

    @email_notifier = Exceptify::EmailNotifier.new(
      email_prefix: "[Dummy ERROR] ",
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      email_headers: {"X-Custom-Header" => "foobar"},
      sections: %w[new_section request session environment backtrace],
      background_sections: %w[new_bkg_section backtrace data],
      pre_callback:
        proc { |_opts, _notifier, _backtrace, _message, message_opts| message_opts[:pre_callback_called] = 1 },
      post_callback:
        proc { |_opts, _notifier, _backtrace, _message, message_opts| message_opts[:post_callback_called] = 1 }
    )

    @controller = HomeController.new
    @controller.process(:index)

    @test_env = Rack::MockRequest.env_for(
      "/",
      "HTTP_HOST" => "test.address",
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_USER_AGENT" => "Rails Testing",
      "action_dispatch.parameter_filter" => ["secret"],
      "HTTPS" => "on",
      "action_controller.instance" => @controller,
      "rack.session.options" => {},
      :params => {id: "foo", secret: "secret"}
    )

    @mail = @email_notifier.create_email(@exception, env: @test_env, data: {message: "My Custom Message"})
  end

  test "create_email builds request email without delivery" do
    assert_empty ActionMailer::Base.deliveries
    assert_respond_to @mail, :deliver_now
  end

  test "sends mail with correct content" do
    assert_equal %("Dummy Notifier" <dummynotifier@example.com>), @mail[:from].value
    assert_equal %w[dummyexceptions@example.com], @mail.to
    assert_equal '[Dummy ERROR] home#index (ZeroDivisionError) "divided by 0"', @mail.subject
    assert_equal "foobar", @mail["X-Custom-Header"].value
    assert_equal "text/plain; charset=UTF-8", @mail.content_type
    assert_equal [], @mail.attachments

    body_fragments = []

    # standard:disable Lint/LiteralInInterpolation
    body_fragments << <<~BODY
      A ZeroDivisionError occurred in home#index:

        divided by 0
        test/exceptify/email_notifier_test.rb:20


      -------------------------------
      New section:
      -------------------------------

        * New text section for testing

      -------------------------------
      Request:
      -------------------------------

        * URL        : https://test.address/?id=foo&secret=secret
        * HTTP Method: GET
        * IP address : 127.0.0.1
        * Parameters : #{{"id" => "foo", "secret" => "[FILTERED]"}}
        * Timestamp  : Sat, 20 Apr 2013 20:58:55 UTC +00:00
        * Server : #{Socket.gethostname}
    BODY

    body_fragments << "    * Rails root : #{Rails.root}\n" if defined?(Rails) && Rails.respond_to?(:root)

    body_fragments << <<~BODY
        * Process: #{Process.pid}

      -------------------------------
      Session:
      -------------------------------

        * session id: [FILTERED]
        * data: {}

      -------------------------------
      Environment:
      -------------------------------

    BODY

    body_fragments << "* action_controller.instance"
    body_fragments << "* rack.errors"
    body_fragments << "[FILTERED]"

    body_fragments << <<~BODY
      -------------------------------
      Backtrace:
      -------------------------------

        test/exceptify/email_notifier_test.rb:20

      -------------------------------
      Data:
      -------------------------------

        * data: #{{message: "My Custom Message"}}


    BODY
    # standard:enable Lint/LiteralInInterpolation
    body_fragments.each do |fragment|
      assert_includes @mail.decode_body, fragment
    end
  end

  test "should not include controller and action names in subject" do
    email_notifier = Exceptify::EmailNotifier.new(
      sender_address: %("Dummy Notifier" <dummynotifier@example.com>),
      exception_recipients: %w[dummyexceptions@example.com],
      include_controller_and_action_names_in_subject: false
    )

    mail = email_notifier.create_email(@exception, env: @test_env)

    assert_empty ActionMailer::Base.deliveries
    assert_equal "[ERROR]  (ZeroDivisionError) \"divided by 0\"", mail.subject
  end
end
