# Refactoring Plan

Last audit: 2026-06-07

## Purpose

Exceptify exists to give Rails and Rack applications a small, self-hosted way to report exceptions to channels teams already use: email, chat, webhooks, and monitoring services.

The gem should stay easy to understand, easy to configure, and easy for open source contributors to maintain. Refactoring should improve correctness, testability, and Rails compatibility without turning the gem into a large framework.

## Implementation Status

Completed: 2026-06-07

All six milestones below have been implemented in the current refactoring pass. The plan remains in the repository as maintenance context for future contributors and follow-up cleanup.

| Milestone | Status | Success Coverage | Failure Coverage | Edge/Null/Boundary Coverage |
| --- | --- | --- | --- | --- |
| 1. Safety and documentation alignment | Done | Documented notifiers map to implementation and docs. | Unsupported notifiers are not documented or generated. | Custom notifier docs are allowed without a built-in implementation. |
| 2. Configuration and registry POROs | Done | `Configuration` and `NotifierRegistry` configure notifiers and ignore rules. | Invalid notifier registration and ignore-condition errors are covered. | Reset/copy behavior does not share mutable state. |
| 3. Dispatcher and middleware isolation | Done | Dispatcher sends selected notifiers; Rack instances keep local options. | Ignored notifications and notifier failures are covered. | Global middleware fallback and all-filtered notifier cases are covered. |
| 4. Notification context POROs | Done | Notification data, request context, hostname, timestamps, and backtrace cleaning are covered. | Missing request env is covered. | Injected clock, hostname, and cleaner are covered. |
| 5. Notifier cleanup | Done | Network notifiers can use injected clients/transports. | Missing required options raise deterministic `ArgumentError`s. | Explicit `fail_silently`, blank URLs, and missing backtraces are covered. |
| 6. Rails adapter cleanup | Done | Runner exceptions notify through the Rails adapter hook. | `SystemExit` is ignored. | Duplicate runner hook installation is guarded. |

Verification completed:

* `bundle exec rake test`
* `bundle exec standardrb`
* `bundle exec rake build`
* Legacy namespace scan

## Principles

Use these principles for every refactor:

* SRP: one object should have one reason to change.
* DI: external clients, clocks, caches, HTTP adapters, Rails state, and registries should be injectable where practical.
* PORO: core behavior should live in plain Ruby objects. Rails should be an adapter layer, not the core architecture.
* KISS: prefer small classes and direct data flow over abstract frameworks.
* YAGNI: do not add a container, plugin system, event bus, or new runtime dependency unless a current problem requires it.
* Backward compatibility: keep the public `Exceptify.configure`, `Exceptify.add_notifier`, and `Exceptify.notify_exception` API unless a breaking change is explicitly planned for a major release.

## Current Strengths

* The public API is small and understandable.
* The gem has focused tests for notifiers, Rack middleware, Rake, Resque, Sidekiq, generators, and require paths.
* Notifiers are mostly small objects that respond to `#call(exception, options)`.
* The gem does not force a hosted error tracker or a large dependency chain.

## Audit Findings

### P0: Global Mutable State In The Core

Files: `lib/exceptify.rb`, `lib/exceptify/modules/error_grouping.rb`, `test/support/exceptify_helper.rb`

The core module stores configuration, ignore rules, notifier registry, testing mode, and error grouping settings in class variables and `mattr_accessor`s. That makes the gem simple to call, but it couples unrelated responsibilities and makes behavior depend on process-global state.

Risks:

* Rack middleware instances are not isolated.
* Test helpers need to reach into class variables to reset state.
* Multi-app or multi-tenant Rack processes can leak configuration.
* Thread safety is unclear because shared hashes and arrays are mutated directly.

Target shape:

* Add `Exceptify::Configuration` as a PORO for settings.
* Add `Exceptify::NotifierRegistry` as a PORO for notifier lookup and lifecycle.
* Keep `Exceptify` as a facade delegating to a default configuration and dispatcher.
* Make reset behavior public and intentional, for tests and reloads.

Acceptance criteria:

* No direct class variable writes from tests.
* `Exceptify.configure` still works.
* `Exceptify.notify_exception` still works.
* Existing tests pass before and after each small step.

### P0: Rack Middleware Mutates Global Configuration

File: `lib/exceptify/rack.rb`

`Exceptify::Rack#initialize` consumes middleware options and writes them into the process-global `Exceptify` module. That means one middleware configuration can affect later requests, other middleware instances, and tests.

Target shape:

* Build a middleware-local configuration from options.
* Inject a dispatcher into the Rack middleware, defaulting to the gem facade.
* Keep Rails initializer configuration as the default path, but do not require Rack-only usage to mutate global state.

Acceptance criteria:

* Two `Exceptify::Rack` instances can use different notifier/ignore settings in the same process.
* Existing Rails middleware usage still works.
* Rack tests cover isolated middleware instances.

### P0: Dispatch Pipeline Has Too Many Responsibilities

File: `lib/exceptify.rb`

`notify_exception` currently handles ignored exceptions, conditional ignores, error grouping, notifier selection, notifier dispatch, and notifier error handling. This violates SRP and makes changes to one policy riskier than needed.

Target shape:

* Add `Exceptify::Dispatcher` for the notification flow.
* Add small policy objects or PORO methods for:
  * ignored exception matching
  * conditional ignores
  * per-notifier ignores
  * error grouping
  * notifier invocation
* Keep the public facade thin.

Acceptance criteria:

* `Exceptify.notify_exception(exception, options)` delegates to the dispatcher.
* Each dispatch step has direct unit tests.
* No behavior change for normal notification flow.

### P1: Notification Context Is Rebuilt In Many Places

Files: `lib/exceptify/modules/formatter.rb`, `lib/exceptify/email_notifier.rb`, `lib/exceptify/slack_notifier.rb`, `lib/exceptify/sns_notifier.rb`, `lib/exceptify/webhook_notifier.rb`, `lib/exceptify/datadog_notifier.rb`, `lib/exceptify/teams_notifier.rb`

Multiple notifiers independently read `env`, build `ActionDispatch::Request`, fetch controller/action names, clean backtraces, merge `exceptify.exception_data`, read Rails app names, call `Socket.gethostname`, and use `Time.current`.

Risks:

* Inconsistent notification content.
* Repeated Rails coupling.
* Harder tests because every notifier needs Rails/request setup.
* Harder future changes to redaction, data merging, hostname, timestamps, and backtrace formatting.

Target shape:

* Add `Exceptify::Notification` or `Exceptify::Event` as a PORO.
* Add `Exceptify::RequestContext` for Rack/Rails request details.
* Add injectable dependencies for clock, hostname, backtrace cleaner, and app name.
* Keep notifiers focused on translating a notification object into provider-specific payloads.

Acceptance criteria:

* Notifiers can be tested with a plain notification object.
* Request extraction is tested once.
* Existing notifier output stays stable unless a change is intentional and documented.

### P1: External Client Dependencies Are Hard-Coded

Files: `lib/exceptify/webhook_notifier.rb`, `lib/exceptify/slack_notifier.rb`, `lib/exceptify/sns_notifier.rb`, `lib/exceptify/datadog_notifier.rb`, `lib/exceptify/teams_notifier.rb`

Some notifiers call `HTTParty`, `Slack::Notifier`, `Aws::SNS::Client`, or `Dogapi` directly. Teams already exposes a partial injectable `httparty` accessor, but the pattern is inconsistent.

Target shape:

* Allow each notifier to receive its transport/client through options.
* Keep default clients for normal users.
* Validate missing optional dependencies with clear error messages.
* Do not add a new HTTP abstraction gem.

Acceptance criteria:

* Each network notifier has tests using an injected fake client.
* Missing optional gems fail with clear configuration errors.
* Existing documented setup still works.

### P1: Silent Configuration Failures

Files: `lib/exceptify/slack_notifier.rb`

Some notifier constructors rescue all errors and silently disable themselves by setting the client/room to `nil`. That hides invalid configuration and makes production failures hard to diagnose.

Target shape:

* Validate required options explicitly.
* Raise `ArgumentError` for invalid configuration during setup.
* If silent behavior is still needed, make it explicit with an option such as `fail_silently: true`.
* Log delivery failures with notifier name and exception details.

Acceptance criteria:

* Missing required notifier options have deterministic tests.
* Invalid notifier configuration is visible to the user.
* No broad `rescue` in notifier constructors without logging or re-raising.

### P1: Optional And Legacy Notifier Surface Needs A Decision

Files: `docs/notifiers/*.md`, `lib/generators/exceptify/templates/exceptify.rb.erb`

Unsupported notifier docs appeared in generated comments without matching maintained implementations.

Target shape:

* Create a support matrix for every notifier:
  * supported
  * legacy but tested
  * deprecated
  * removed from docs
* Remove docs and generator comments for unsupported notifiers.
* If a legacy notifier remains, add explicit tests and maintenance notes.

Acceptance criteria:

* README, docs, generator comments, and implementation list agree.
* Users cannot configure a documented notifier that has no implementation.
* Deprecations are in `CHANGELOG.rdoc` and README before removal.

### P2: Rails Coupling Is Spread Through Core And Notifiers

Files: `lib/exceptify.rb`, `lib/exceptify/rack.rb`, `lib/exceptify/rails.rb`, `lib/exceptify/modules/backtrace_cleaner.rb`, `lib/exceptify/modules/formatter.rb`, `lib/exceptify/email_notifier.rb`, `lib/exceptify/teams_notifier.rb`

Rails checks and Rails-specific behavior are spread through multiple files. The gem should support Rails well, but the core should remain usable as plain Rack/Ruby code.

Target shape:

* Keep `lib/exceptify/rails.rb` as the Rails integration boundary.
* Move Rails-specific defaults into a Rails adapter.
* Keep core notification/context objects Rails-optional.
* Inject Rails cache, logger, app name, and backtrace cleaner through configuration.

Acceptance criteria:

* `require "exceptify"` does not require Rails.
* `require "exceptify/rack"` works in non-Rails Rack apps.
* Rails-specific behavior is covered by Rails integration tests.

### P2: Error Grouping Needs Isolation And Safer Defaults

File: `lib/exceptify/modules/error_grouping.rb`

Error grouping is mixed into the core module and depends on mutable global cache settings. Cache read/write failures are converted to fallback memory store behavior, but the current `log_cache_error` method only returns a string and does not log it.

Target shape:

* Extract `Exceptify::ErrorGrouping` into a PORO service.
* Inject cache, period, trigger, fallback cache, and logger.
* Log cache failures when fallback behavior is used.
* Use a stable key builder object so grouping behavior is testable.

Acceptance criteria:

* Cache failure tests assert logging and fallback behavior.
* Grouping can be tested without mutating `Exceptify`.
* Default behavior remains unchanged unless documented.

### P2: Email Notifier Mixes Mailer Definition, Payload Building, And Delivery

File: `lib/exceptify/email_notifier.rb`

`EmailNotifier` defines an ActionMailer subclass dynamically, builds request/background state, renders templates, handles delivery settings, and sends the message.

Target shape:

* Extract payload/context building from mailer rendering.
* Keep ActionMailer-specific code in a small mailer adapter.
* Replace `MissingController#method_missing` with a small null object that exposes the methods actually used.
* Keep template paths stable.

Acceptance criteria:

* Subject building is unit-tested without ActionMailer.
* Request/background context building is unit-tested without delivery.
* Email delivery tests still cover ActionMailer integration.

### P2: Documentation Quality And Maintenance Hygiene

Files: `README.md`, `docs/notifiers/*.md`, `examples/sinatra/*`, `test/support/exceptify_helper.rb`

The docs are useful but still include old wording patterns, grammar issues, stale provider docs, and inconsistent examples. This increases support cost for new maintainers.

Target shape:

* Keep README focused on setup, common workflows, and links.
* Keep notifier docs consistent:
  * required gems
  * minimal setup
  * options
  * example notification data
  * troubleshooting
* Add a release checklist and compatibility policy.
* Fix typos in docs and test helper comments.

Acceptance criteria:

* Every documented notifier has implementation and tests.
* Examples run against the current gem name and version.
* README stays concise and does not duplicate every notifier option.

## Recommended Order Of Work

### Milestone 1: Safety And Documentation Alignment

1. Add this refactoring plan to the repository.
2. Add a support matrix for notifiers in README or docs.
3. Remove or mark unsupported notifier documentation.
4. Decide legacy notifier status.
5. Fix doc typos and stale examples.
6. Add CI checks for:
   * tests
   * StandardRB
   * gem build
   * package contents
   * old namespace scan

### Milestone 2: Configuration And Registry POROs

1. Add `Exceptify::Configuration`.
2. Add `Exceptify::NotifierRegistry`.
3. Make `Exceptify.configure` mutate the default configuration object.
4. Make tests reset configuration through a public API.
5. Keep facade compatibility.

### Milestone 3: Dispatcher And Middleware Isolation

1. Add `Exceptify::Dispatcher`.
2. Move ignore/grouping/notifier dispatch flow into the dispatcher.
3. Make Rack middleware receive a configuration or dispatcher.
4. Add tests proving two Rack middleware instances stay isolated.

### Milestone 4: Notification Context POROs

1. Add notification/request context objects.
2. Move request extraction, data merging, timestamps, hostnames, app names, and backtrace cleaning into those objects.
3. Update notifiers one at a time to consume the context.
4. Keep old notifier call signatures through adapters during the transition.

### Milestone 5: Notifier Cleanup

1. Add explicit option validation.
2. Add client injection for network notifiers.
3. Remove broad silent rescues.
4. Normalize error handling and logging.
5. Revisit legacy notifiers after support matrix decisions.

### Milestone 6: Rails Adapter Cleanup

1. Keep Rails setup in `exceptify/rails`.
2. Move Rails cache/logger/backtrace/app-name defaults into Rails adapter code.
3. Guard runner `at_exit` registration against duplicate installation.
4. Add Rails integration tests for generator, middleware, rake, and runner behavior.

## Definition Of Done

Each refactoring PR should satisfy:

* Public API compatibility is preserved or deprecation is documented.
* `bundle exec rake test` passes.
* `bundle exec standardrb` passes.
* `bundle exec rake build` passes.
* The package does not include old namespace files.
* New POROs have direct unit tests.
* The change removes or isolates responsibility instead of adding abstraction for its own sake.

## Non-Goals

* Do not build a hosted error tracking product.
* Do not add background delivery, retries, persistence, dashboards, or grouping UI unless a future issue proves the need.
* Do not introduce a dependency injection framework.
* Do not rewrite all notifiers in one PR.
* Do not change the public API only for naming preference.
