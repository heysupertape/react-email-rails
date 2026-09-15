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

Vitest 5 declares Node.js 22.12+ in its own `engines`, but the published package stays on `>=20.19.0` to match Vite's supported range. CI still runs the Vite suite on Node 20 so that range keeps real coverage; the test runner is a dev-only tool and does not constrain consumers. If a future Vitest release starts using APIs that Node 20 lacks, the Node 20 CI jobs are the thing that will break first.

The Ruby gem version in `lib/react_email_rails/version.rb` is the package version source of truth. The renderer protocol version in `lib/react_email_rails/render_protocol.rb` is also synced into the Vite package. Run `cd vite && pnpm run sync:version` after changing either one.

## Publishing

Releases are tag-driven. Pushing `vX.Y.Z` to GitHub runs `.github/workflows/release.yml`, publishes the Ruby gem to RubyGems, publishes the Vite package to npm, and creates the GitHub Release with the built `.gem` and `.tgz` artifacts.

### Patch, Minor, and Major Releases

Update the source-of-truth gem version in `lib/react_email_rails/version.rb`, update `CHANGELOG.md`, and commit the release prep on `main` or open and merge a release pull request. Then tag the release commit:

```sh
bin/release
```

`bin/release` fetches `origin/main`, validates the version and changelog, infers whether the release is patch, minor, major, or initial from the existing SemVer tags, creates the annotated `vX.Y.Z` tag on `origin/main`, and pushes it after confirmation.

The GitHub release workflow handles the rest. If publishing fails before both registries are updated, do not reuse the same version unless neither registry accepted it; bump to the next patch version and release again.
