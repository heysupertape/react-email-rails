# Contributing

Bug reports and pull requests are welcome.

## Development Setup

Install Ruby dependencies:

```sh
bundle install
```

Install the Vite package dependencies:

```sh
cd vite
pnpm install
```

## Checks

Run the same checks used for local development:

```sh
ruby scripts/check_version_sync.rb
bin/test
bin/lint
cd vite && pnpm run build
```

## Versioning

The Ruby gem version in `lib/react_email_rails/version.rb` is the source of truth. The npm package version in `vite/package.json` is synced from it during `pnpm pack` through the package `prepack` script.

Before opening a release pull request, verify:

```sh
ruby scripts/check_version_sync.rb
bundle exec rake build
cd vite && pnpm pack --dry-run
```

## Pull Requests

Keep changes focused and include tests for behavior changes. For public API or setup changes, update `README.md` in the same pull request.
