# Contributing

Bug reports and pull requests are welcome.

## Development

Install dependencies:

```sh
bundle install
cd vite && pnpm install
```

Run the core checks before opening a pull request:

```sh
ruby scripts/check_version_sync.rb
bin/test
bin/lint
cd vite && pnpm run build
```

The Ruby gem version in `lib/react_email_rails/version.rb` is the package version source of truth. The renderer protocol version in `lib/react_email_rails/render_protocol.rb` is also synced into the Vite package. Run `cd vite && pnpm run sync:version` after changing either one.

## Release Checks

Before publishing, verify both packages can be built:

```sh
bundle exec rake build
cd vite && pnpm pack --dry-run
```
