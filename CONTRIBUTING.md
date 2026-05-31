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

## Publishing

Releases are tag-driven. Pushing `vX.Y.Z` to GitHub runs `.github/workflows/release.yml`, publishes the Ruby gem to RubyGems, publishes the Vite package to npm, and creates the GitHub Release with the built `.gem` and `.tgz` artifacts.

### One-time Registry Setup

Configure RubyGems trusted publishing:

- For the first release, create a pending trusted publisher for gem `react-email-rails`.
- Repository owner: `heysupertape`
- Repository name: `react-email-rails`
- Workflow filename: `release.yml`
- Environment: leave blank

Configure npm trusted publishing for package `react-email-rails`:

- Publisher: GitHub Actions
- Organization or user: `heysupertape`
- Repository: `react-email-rails`
- Workflow filename: `release.yml`
- Environment name: leave blank
- Allowed actions: `npm publish`

npm only allows trusted publishing to be configured after the package already exists. For the first npm release only, add an `NPM_TOKEN` repository secret with permission to publish `react-email-rails`, push the first release tag, then delete the secret after the package is published. Once the package exists, configure trusted publishing in the npm UI or with:

```sh
cd vite
npm install --global npm@^11.10.0
npm trust github react-email-rails --repo heysupertape/react-email-rails --file release.yml --allow-publish
```

Do not add RubyGems tokens to GitHub secrets. Do not keep an npm publish token in GitHub after the first package publish. Normal releases use short-lived OIDC credentials from the registries.

### Patch, Minor, and Major Releases

Prepare the version bump:

```sh
ruby scripts/prepare_release.rb patch
# or: ruby scripts/prepare_release.rb minor
# or: ruby scripts/prepare_release.rb major
```

Replace the generated `CHANGELOG.md` TODO entry with the actual release notes, then run the checks:

```sh
ruby scripts/check_version_sync.rb
bin/test
bin/lint
cd vite && pnpm run ci && pnpm pack --dry-run
```

Commit the release prep on `main` or open and merge a release pull request. Then tag the release commit:

```sh
git switch main
git pull --ff-only origin main
VERSION=$(ruby -r ./lib/react_email_rails/version -e 'print ReactEmailRails::VERSION')
ruby scripts/check_release_tag.rb "v$VERSION"
git tag -a "v$VERSION" -m "v$VERSION"
git push origin "v$VERSION"
```

The GitHub release workflow handles the rest. If publishing fails before both registries are updated, do not reuse the same version unless neither registry accepted it; bump to the next patch version and release again.
