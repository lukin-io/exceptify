# Releasing Exceptify

## First RubyGems.org Publish

The `exceptify` gem is built from `exceptify.gemspec`. RubyGems.org receives the
built `.gem` file, not the Git repository.

Run the first publish manually:

```sh
bundle install
bundle exec rake test
bundle exec standardrb
gem build --strict exceptify.gemspec
gem signin
gem push exceptify-1.0.0.gem
```

RubyGems.org versions are immutable. If a pushed gem needs any code or metadata
change, bump `Exceptify::VERSION` and publish a new version.

## Trusted Publishing Setup

Before CI can publish to RubyGems.org, configure RubyGems.org Trusted Publishing.
For a brand-new gem, create a pending trusted publisher before pushing the release
tag. If the gem was published manually first, add the trusted publisher to the
existing gem:

- Gem name: `exceptify`
- GitHub repository owner: `lukin-io`
- GitHub repository name: `exceptify`
- Workflow filename: `gem-push.yml`
- Environment: `release`

The workflow publishes tagged releases to both GitHub Packages and RubyGems.org.
RubyGems.org publishing uses GitHub OIDC through `rubygems/release-gem@v1`, so no
long-lived `RUBYGEMS_AUTH_TOKEN` secret is needed.

## Release Flow

1. Update `Exceptify::VERSION` in `lib/exceptify/version.rb`.
2. Update `CHANGELOG.rdoc`.
3. Commit the changes.
4. Create a matching tag:

   ```sh
   git tag v1.0.0
   git push origin main
   git push origin v1.0.0
   ```

The CI workflow verifies that the tag name matches the gem version before
publishing.
