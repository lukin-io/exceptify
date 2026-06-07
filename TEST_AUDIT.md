# Test Audit

Last audit: 2026-06-07

## Scope

This audit reviewed the pre-refactor test suite after the new PORO and notifier tests were added. The goal was to find old tests that still gave weak regression coverage or missed important failure and boundary behavior.

## Findings Addressed

### Webhook Notifier

Old gap: one test stubbed `WebhookNotifier.new` and `#call`, then asserted the stubbed response. That did not test the real payload builder.

Improvement:

* Replaced the stubbed response test with a real request-env payload assertion.
* Added callback assertions for `pre_callback` and `post_callback`.
* Fixed a bug where the payload used `$PROCESS_ID`, which is nil unless Ruby's English aliases are loaded. It now uses `Process.pid`.

### Rake Integration

Old gap: only the exception path was covered.

Improvement:

* Added coverage that successful tasks do not notify.
* Added coverage that `SystemExit` is re-raised but does not notify.
* Cleared Rake tasks between tests to avoid order coupling.

### Resque Integration

Old gap: failure notification was covered, but successful jobs were not.

Improvement:

* Added coverage that successful Resque jobs do not notify.

### Sidekiq Integration

Old gap: the compatibility branch for Sidekiq handler calls without a config argument was only covered when running old Sidekiq versions.

Improvement:

* Added direct handler coverage for the no-config call shape.

### Teams Notifier

Old gap: injected transport from constructor was not covered, missing `webhook_url` was not covered, and two assertions used `assert` where `assert_equal` was required.

Improvement:

* Added constructor-injected HTTP client coverage.
* Added missing `webhook_url` failure coverage.
* Replaced weak assertions with exact comparisons.

### Datadog Notifier

Old gap: missing client setup raised a raw `KeyError`, and request formatting used the same nil process-id alias as Webhook.

Improvement:

* Added explicit missing-client validation.
* Added request-body assertion for process id.
* Switched request formatting to `Process.pid`.

### Rack Middleware Tests

Old gap: several tests used broad rescue blocks with `flunk`, which made the expected failure mode less clear.

Improvement:

* Replaced broad rescue blocks with `assert_raises`.
* Fixed a test name typo.

### Email Notifier

Old gap: email coverage was broad but integration-heavy. Many tests built and delivered mail even when the behavior under test was only subject or payload construction.

Improvement:

* Converted rendering, subject, recipient, encoding, and multipart assertions to use `create_email` without delivery.
* Kept explicit ActionMailer delivery tests for `#call` and custom `deliver_with`.
* Added focused subject tests for digit normalization, truncation, and request-env option overrides.
* Added focused payload tests for merged request/explicit data and empty data boundaries.

## Remaining Watch Items

No remaining test-audit watch items are open after the supported notifier set was narrowed.
