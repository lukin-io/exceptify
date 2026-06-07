# Exceptify

[![Gem Version](https://badge.fury.io/rb/exceptify.svg)](https://badge.fury.io/rb/exceptify)
[![Build Status](https://github.com/lukin-io/exceptify/actions/workflows/ci.yml/badge.svg)](https://github.com/lukin-io/exceptify/actions/workflows/ci.yml)

Exceptify sends exception reports from Rails and Rack applications to the channels your team already watches: email, chat, webhooks, and monitoring tools.

This repository is maintained by [@lukin-io](https://github.com/lukin-io) as `lukin-io/exceptify` with the `exceptify` gem name and `Exceptify` API. Version `1.0.0` starts the maintained Exceptify release line.

## Quick Start

Add the gem to your Rails application's `Gemfile`:

```ruby
gem "exceptify"
```

Install it and generate the initializer:

```bash
bundle install
bundle exec rails generate exceptify:install
```

Configure at least one notifier:

```ruby
# config/initializers/exceptify.rb
require "exceptify/rails"
require "exceptify/rake"

Exceptify.configure do |config|
  config.add_notifier :email, {
    email_prefix: "[#{Rails.env.upcase}] ",
    sender_address: %("Exceptify" <notifier@example.com>),
    exception_recipients: %w[exceptions@example.com]
  }

  config.ignore_if do |_exception, _options|
    Rails.env.local?
  end
end
```

Email delivery uses your application's ActionMailer configuration. See [ActionMailer configuration](docs/notifiers/email.md#actionmailer-configuration) if emails do not send.

## How To Test It

After configuring a notifier, trigger a real exception in a non-production environment.

```ruby
# config/routes.rb
get "/exceptify_test", to: proc {
  raise "Exceptify test"
}
```

Start Rails, visit `/exceptify_test`, and confirm the notification arrives. Remove the route after testing.

## Contents

* [Quick Start](#quick-start)
* [How To Test It](#how-to-test-it)
* [What It Does](#what-it-does)
* [Compatibility](#compatibility)
* [Installation](#installation)
* [Rails Setup](#rails-setup)
* [Common Workflows](#common-workflows)
* [Notifiers](#notifiers)
* [Noise Control](#noise-control)
* [Production Checklist](#production-checklist)
* [Background Jobs](#background-jobs)
* [Rack and Sinatra](#rack-and-sinatra)
* [Maintenance](#maintenance)
* [Development](#development)
* [License](#license)

## What It Does

Exceptify installs a Rack middleware that watches for unhandled exceptions during web requests and sends a notification with request, session, environment, backtrace, and optional application data.

Use it when you want a small, self-hosted notification layer for exceptions without adopting a hosted error tracker.

It supports:

* Rails integration through a generator and initializer.
* Rack middleware configuration for Rails, Sinatra, and other Rack apps.
* Built-in notifiers for email, Slack, Teams, Amazon SNS, Datadog, and webhooks.
* Manual reporting for rescued exceptions, background jobs, scripts, rake tasks, and runners.
* Ignore rules, crawler filtering, per-notifier filtering, and repeated-error grouping.

## Compatibility

* Exceptify 1.0.0 or newer.
* Ruby 3.4.4 or newer.
* Rails 8.0.2 or newer, below Rails 9.
* Rack applications, including Sinatra.

The changelog starts at `1.0.0` for the maintained `exceptify` release line.

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "exceptify"
```

Install it:

```bash
bundle install
```

To use this maintained repository directly from Git:

```ruby
gem "exceptify", git: "https://github.com/lukin-io/exceptify.git"
```

For local gem development, point a test application at your checkout:

```ruby
gem "exceptify", path: "../exceptify"
```

If the application should keep a Git source in its `Gemfile` while Bundler uses a local checkout, configure a local override from that application:

```bash
bundle config set local.exceptify ../exceptify
bundle install
```

## Rails Setup

Generate the Rails initializer:

```bash
bundle exec rails generate exceptify:install
```

The generated file is written to `config/initializers/exceptify.rb`.

Keep the gem available to every environment that loads the initializer. If you want notifications only in production, keep the gem outside a `production`-only bundle group and add an ignore rule for local environments.

### Initializer Notes

The generated initializer should load the Rails and Rake integrations, then register one or more notifiers. The email example in [Quick Start](#quick-start) is enough for a first setup; add other notifiers from [Notifiers](#notifiers) as needed.

### Rails Runner Support

If you want `rails runner` commands to report exceptions, load the Rails integration from `config/application.rb` below `Bundler.require`:

```ruby
# config/application.rb
require "exceptify/rails"
```

The initializer is too late for runner callbacks. You can still keep notifier configuration in `config/initializers/exceptify.rb`.
The runner hook is guarded, so loading the integration more than once does not install duplicate `at_exit` callbacks.

## Common Workflows

### Send to Email and Slack

Slack notifications require the `slack-notifier` gem:

```ruby
gem "slack-notifier"
```

Then register both notifiers:

```ruby
Exceptify.configure do |config|
  config.add_notifier :email, {
    email_prefix: "[#{Rails.env.upcase}] ",
    sender_address: %("Exceptify" <notifier@example.com>),
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
  before_action :prepare_exceptify_notification

  private

  def prepare_exceptify_notification
    request.env["exceptify.exception_data"] = {
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
    Exceptify.notify_exception(
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
  Exceptify.notify_exception(
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

Built-in notifier docs and support status:

| Notifier | Status | Docs |
| --- | --- | --- |
| Email | Supported | [Email](docs/notifiers/email.md) |
| Slack | Supported | [Slack](docs/notifiers/slack.md) |
| Teams | Supported | [Teams](docs/notifiers/teams.md) |
| Amazon SNS | Supported | [Amazon SNS](docs/notifiers/sns.md) |
| Datadog | Supported | [Datadog](docs/notifiers/datadog.md) |
| WebHook | Supported | [WebHook](docs/notifiers/webhook.md) |
| Custom notifiers | Supported extension point | [Custom notifiers](docs/notifiers/custom.md) |

### Notifier Setup Rules

Network notifiers validate required options during setup. Missing `webhook_url`, `url`, or AWS credentials raise `ArgumentError` instead of silently disabling notifications.

For tests, custom transports, or apps that already wrap provider clients, pass an injected client:

```ruby
Exceptify.configure do |config|
  config.add_notifier :webhook, {
    url: "https://example.com/exception-webhook",
    http_client: MyHTTPClient
  }

  config.add_notifier :sns, {
    topic_arn: "arn:aws:sns:us-east-1:123456789012:exceptions",
    client: Aws::SNS::Client.new(region: "us-east-1")
  }
end
```

Slack accepts `notifier:` for a prebuilt Slack client. Use `fail_silently: true` only as a temporary compatibility option while migrating old silent configurations.

You can also register any object that responds to `#call(exception, options)`:

```ruby
Exceptify.configure do |config|
  config.add_notifier :logger, lambda { |exception, options|
    Rails.logger.error(
      "[exceptify] #{exception.class}: #{exception.message} #{options[:data].inspect}"
    )
  }
end
```

## Noise Control

### Ignore Known Exceptions

```ruby
Exceptify.configure do |config|
  config.ignored_exceptions += %w[
    ActionView::TemplateError
    MyApp::ExpectedError
  ]
end
```

The default ignored exceptions include common routing, record-not-found, and invalid-parameter errors.

### Ignore Crawlers

```ruby
Exceptify.configure do |config|
  config.ignore_crawlers %w[Googlebot bingbot]
end
```

### Ignore by Condition

```ruby
Exceptify.configure do |config|
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
Exceptify.configure do |config|
  config.ignore_notifier_if(:slack) do |exception, _options|
    exception.is_a?(ActionController::RoutingError)
  end
end
```

### Group Repeated Errors

Error grouping prevents notification floods for the same exception. With the default trigger, notifications are sent at counts 1, 2, 4, 8, 16, and so on.

```ruby
Exceptify.configure do |config|
  config.error_grouping = true
  config.error_grouping_cache = Rails.cache
  config.error_grouping_period = 5.minutes

  config.notification_trigger = lambda { |_exception, count|
    count == 1 || (count % 10).zero?
  }
end
```

## Production Checklist

Before relying on exception notifications in production:

* Configure at least one notifier.
* Verify delivery with a real test exception in staging.
* Confirm ActionMailer delivery settings if using email.
* Filter secrets with `config.filter_parameters`.
* Ignore local and test environments.
* Add crawler or health-check ignores if they create noise.
* Enable error grouping for high-traffic applications.
* Make sure background jobs are covered separately from web requests.

## Background Jobs

The Rack middleware only catches exceptions during web requests. For jobs and command-line work, use one of the integrations below.

### Rake Tasks

The generated initializer includes:

```ruby
require "exceptify/rake"
```

That reports unhandled exceptions from rake tasks.

### Rails Runner

For `rails runner`, require the Rails integration from `config/application.rb` as shown in [Rails Runner Support](#rails-runner-support).

### Sidekiq and Resque

Generate an initializer with the integration you need:

```bash
bundle exec rails generate exceptify:install --sidekiq
```

or:

```bash
bundle exec rails generate exceptify:install --resque
```

### Manual Job Reporting

If a job system is not integrated, report exceptions directly:

```ruby
class RebuildSearchIndexJob
  def perform(account_id)
    RebuildSearchIndex.call(account_id)
  rescue => exception
    Exceptify.notify_exception(
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
require "exceptify"

use Exceptify::Rack,
  email: {
    email_prefix: "[RACK ERROR] ",
    sender_address: %("Exceptify" <notifier@example.com>),
    exception_recipients: %w[exceptions@example.com]
  },
  ignore_exceptions: ["Sinatra::NotFound"],
  ignore_cascade_pass: true
```

Options passed directly to `Exceptify::Rack` are local to that middleware instance. To use one application-wide configuration, configure `Exceptify` once and mount the middleware without notifier options:

```ruby
require "exceptify"

Exceptify.configure do |config|
  config.add_notifier :email, {
    sender_address: %("Exceptify" <notifier@example.com>),
    exception_recipients: %w[exceptions@example.com]
  }
end

use Exceptify::Rack
```

Sinatra users can also review the [example application](examples/sinatra).

## Maintenance

This repository is the current home for the `exceptify` gem. Maintenance focuses on modern Ruby and Rails support, clear documentation, and practical bug fixes around the `Exceptify` API.

Issues and pull requests are welcome when they include enough context to reproduce the behavior.
The current refactoring direction is tracked in [REFACTORING.md](REFACTORING.md).

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
