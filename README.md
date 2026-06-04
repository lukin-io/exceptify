# Exception Notification

[![Gem Version](https://badge.fury.io/rb/exception_notification.svg)](https://badge.fury.io/rb/exception_notification)
[![Build Status](https://github.com/lukin-io/exceptify/actions/workflows/ci.yml/badge.svg)](https://github.com/lukin-io/exceptify/actions/workflows/ci.yml)

`exception_notification` sends exception reports from Rails and Rack applications to the channels your team already watches: email, chat, webhooks, and monitoring tools.

This repository is maintained by [@lukin-io](https://github.com/lukin-io) as `lukin-io/exceptify`, while keeping the existing gem name and public API compatible for applications that already use `exception_notification`.

## Contents

* [What It Does](#what-it-does)
* [Compatibility](#compatibility)
* [Installation](#installation)
* [Rails Setup](#rails-setup)
* [Common Workflows](#common-workflows)
* [Notifiers](#notifiers)
* [Noise Control](#noise-control)
* [Background Jobs](#background-jobs)
* [Rack and Sinatra](#rack-and-sinatra)
* [Development](#development)
* [License](#license)

## What It Does

Exception Notification installs a Rack middleware that watches for unhandled exceptions during web requests and sends a notification with request, session, environment, backtrace, and optional application data.

Use it when you want a small, self-hosted notification layer for exceptions without adopting a hosted error tracker.

It supports:

* Rails integration through a generator and initializer.
* Rack middleware configuration for Rails, Sinatra, and other Rack apps.
* Built-in notifiers for email, Slack, Mattermost, Teams, IRC, Amazon SNS, Google Chat, Datadog, HipChat, and webhooks.
* Manual reporting for rescued exceptions, background jobs, scripts, rake tasks, and runners.
* Ignore rules, crawler filtering, per-notifier filtering, and repeated-error grouping.

## Compatibility

* Ruby 3.2 or newer.
* Rails 7.1 or newer, including Rails 8.
* Rack applications, including Sinatra.

The gem has a long history in the Rails ecosystem. The original code was extracted from Rails years ago, and this repository continues maintenance for modern Ruby and Rails versions.

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "exception_notification"
```

Install it:

```bash
bundle install
```

To use this maintained repository directly before a release is published to RubyGems:

```ruby
gem "exception_notification", git: "https://github.com/lukin-io/exceptify.git"
```

For local gem development, point a test application at your checkout:

```ruby
gem "exception_notification", path: "../exceptify"
```

If the application should keep a Git source in its `Gemfile` while Bundler uses a local checkout, configure a local override from that application:

```bash
bundle config set local.exception_notification ../exceptify
bundle install
```

## Rails Setup

Generate the Rails initializer:

```bash
bundle exec rails generate exception_notification:install
```

The generated file is written to `config/initializers/exception_notification.rb`.

Keep the gem available to every environment that loads the initializer. If you want notifications only in production, keep the gem outside a `production`-only bundle group and add an ignore rule for local environments.

### Minimal Email Setup

```ruby
# config/initializers/exception_notification.rb
require "exception_notification/rails"
require "exception_notification/rake"

ExceptionNotification.configure do |config|
  config.add_notifier :email, {
    email_prefix: "[#{Rails.env.upcase}] ",
    sender_address: %("Exception Notifier" <notifier@example.com>),
    exception_recipients: %w[exceptions@example.com]
  }

  config.ignore_if do |_exception, _options|
    Rails.env.local?
  end
end
```

Email delivery uses your application's ActionMailer configuration. If emails do not send, check [ActionMailer configuration](docs/notifiers/email.md#actionmailer-configuration) first.

### Rails Runner Support

If you want `rails runner` commands to report exceptions, load the Rails integration from `config/application.rb` below `Bundler.require`:

```ruby
# config/application.rb
require "exception_notification/rails"
```

The initializer is too late for runner callbacks. You can still keep notifier configuration in `config/initializers/exception_notification.rb`.

## Common Workflows

### Send to Email and Slack

Slack notifications require the `slack-notifier` gem:

```ruby
gem "slack-notifier"
```

Then register both notifiers:

```ruby
ExceptionNotification.configure do |config|
  config.add_notifier :email, {
    email_prefix: "[#{Rails.env.upcase}] ",
    sender_address: %("Exception Notifier" <notifier@example.com>),
    exception_recipients: %w[exceptions@example.com]
  }

  if (webhook_url = Rails.application.credentials.dig(:slack, :exceptions_webhook_url))
    config.add_notifier :slack, {
      webhook_url: webhook_url,
      channel: "#exceptions",
      additional_parameters: {
        mrkdwn: true
      }
    }
  end
end
```

### Attach Request Context

Store application data in the request environment before an exception is raised:

```ruby
class ApplicationController < ActionController::Base
  before_action :prepare_exception_notification

  private

  def prepare_exception_notification
    request.env["exception_notifier.exception_data"] = {
      current_user_id: current_user&.id,
      account_id: current_account&.id,
      request_id: request.request_id
    }
  end
end
```

That data is included in supported notifier payloads and email sections.

### Report a Handled Controller Error

Middleware only sees exceptions that continue up the Rack stack. If a controller rescues an error, notify manually:

```ruby
class OrdersController < ApplicationController
  rescue_from PaymentGateway::Timeout, with: :payment_gateway_timeout

  private

  def payment_gateway_timeout(exception)
    ExceptionNotifier.notify_exception(
      exception,
      env: request.env,
      data: {
        order_id: params[:id],
        request_id: request.request_id
      }
    )

    render json: {error: "payment_gateway_timeout"}, status: :bad_gateway
  end
end
```

### Report from Plain Ruby Code

```ruby
begin
  ImportCustomers.call(file_path)
rescue => exception
  ExceptionNotifier.notify_exception(
    exception,
    data: {
      job: "ImportCustomers",
      file_path: file_path
    }
  )

  raise
end
```

### Filter Sensitive Parameters

Exception emails can include request parameters. Use Rails parameter filtering for secrets:

```ruby
# config/application.rb
config.filter_parameters += [
  :password,
  :password_confirmation,
  :credit_card_number,
  :secret_details
]
```

## Notifiers

Built-in notifier docs:

* [Email](docs/notifiers/email.md)
* [Slack](docs/notifiers/slack.md)
* [Mattermost](docs/notifiers/mattermost.md)
* [Teams](docs/notifiers/teams.md)
* [IRC](docs/notifiers/irc.md)
* [Amazon SNS](docs/notifiers/sns.md)
* [Google Chat](docs/notifiers/google_chat.md)
* [Datadog](docs/notifiers/datadog.md)
* [HipChat](docs/notifiers/hipchat.md)
* [WebHook](docs/notifiers/webhook.md)
* [Custom notifiers](docs/notifiers/custom.md)

You can also register any object that responds to `#call(exception, options)`:

```ruby
ExceptionNotification.configure do |config|
  config.add_notifier :logger, lambda { |exception, options|
    Rails.logger.error(
      "[exception_notification] #{exception.class}: #{exception.message} #{options[:data].inspect}"
    )
  }
end
```

## Noise Control

### Ignore Known Exceptions

```ruby
ExceptionNotification.configure do |config|
  config.ignored_exceptions += %w[
    ActionView::TemplateError
    MyApp::ExpectedError
  ]
end
```

The default ignored exceptions include common routing, record-not-found, and invalid-parameter errors.

### Ignore Crawlers

```ruby
ExceptionNotification.configure do |config|
  config.ignore_crawlers %w[Googlebot bingbot]
end
```

### Ignore by Condition

```ruby
ExceptionNotification.configure do |config|
  config.ignore_if do |exception, options|
    path = options.dig(:env, "PATH_INFO")

    Rails.env.local? ||
      path == "/health" ||
      exception.message.match?(/Couldn't find Page with ID=/)
  end
end
```

### Ignore Only One Notifier

Use per-notifier filtering when email should still send but chat should stay quiet, or the reverse:

```ruby
ExceptionNotification.configure do |config|
  config.ignore_notifier_if(:slack) do |exception, _options|
    exception.is_a?(ActionController::RoutingError)
  end
end
```

### Group Repeated Errors

Error grouping prevents notification floods for the same exception. With the default trigger, notifications are sent at counts 1, 2, 4, 8, 16, and so on.

```ruby
ExceptionNotification.configure do |config|
  config.error_grouping = true
  config.error_grouping_cache = Rails.cache
  config.error_grouping_period = 5.minutes

  config.notification_trigger = lambda { |_exception, count|
    count == 1 || (count % 10).zero?
  }
end
```

## Background Jobs

The Rack middleware only catches exceptions during web requests. For jobs and command-line work, use one of the integrations below.

### Rake Tasks

The generated initializer includes:

```ruby
require "exception_notification/rake"
```

That reports unhandled exceptions from rake tasks.

### Rails Runner

For `rails runner`, require the Rails integration from `config/application.rb` as shown in [Rails Runner Support](#rails-runner-support).

### Sidekiq and Resque

Generate an initializer with the integration you need:

```bash
bundle exec rails generate exception_notification:install --sidekiq
```

or:

```bash
bundle exec rails generate exception_notification:install --resque
```

### Manual Job Reporting

If a job system is not integrated, report exceptions directly:

```ruby
class RebuildSearchIndexJob
  def perform(account_id)
    RebuildSearchIndex.call(account_id)
  rescue => exception
    ExceptionNotifier.notify_exception(
      exception,
      data: {
        job: self.class.name,
        account_id: account_id
      }
    )

    raise
  end
end
```

## Rack and Sinatra

Use the Rack middleware directly when you are not using the Rails generator, or when you need Rack-only options such as `ignore_cascade_pass`.

```ruby
require "exception_notification"

use ExceptionNotification::Rack,
  email: {
    email_prefix: "[RACK ERROR] ",
    sender_address: %("Exception Notifier" <notifier@example.com>),
    exception_recipients: %w[exceptions@example.com]
  },
  ignore_exceptions: ["Sinatra::NotFound"],
  ignore_cascade_pass: true
```

Sinatra users can also review the [example application](examples/sinatra).

## Development

Install dependencies:

```bash
bundle install
```

Run tests:

```bash
bundle exec rake test
```

Open a console with the gem loaded:

```bash
bundle exec rake console
```

Build the gem locally:

```bash
bundle exec rake build
```

Pull requests and issues are welcome. Please read the [Contributing Guide](CONTRIBUTING.md) and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT license](MIT-LICENSE).

Maintainer: [@lukin-io](https://github.com/lukin-io)
