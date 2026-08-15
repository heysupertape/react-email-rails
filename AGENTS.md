# AGENTS.md

## Cursor Cloud specific instructions

This repo is a **library**, not a runnable app. It ships two version-locked packages of `react-email-rails`:

- A **Ruby gem** at the repo root (`lib/`, gemspec) that hooks React Email into Action Mailer.
- An **npm/Vite package** in `vite/` (a Vite plugin + Node renderer that renders the React email components).

There is no long-running server to start; "running" the project means running its test suites and, optionally, exercising the Node renderer directly.

### Toolchain (already provisioned by the startup update script)

- **Ruby** is provided by `mise` (Ruby `4.0.6`), not apt (apt only offers 3.2, which is too old; the gem needs `>= 3.3`). Interactive shells get it via `~/.bashrc` (`mise activate`). In a **non-interactive** shell (scripts, `bin/*`, CI-style one-liners) Ruby/`bundle` may not be on `PATH` — prefix with:
  `eval "$(/home/ubuntu/.local/bin/mise activate bash --shims)"`
  `bundle` resolves to `4.0.10` via the shim, matching `Gemfile.lock`'s `BUNDLED WITH`.
- **Node** (v22) and **pnpm** are preinstalled. The JS package lives in `vite/` and requires Node `>= 20.19`.

### Commands (see `CONTRIBUTING.md`, `bin/`, and `vite/package.json` for the source of truth)

- Full check suite: `bin/test` (version sync + `bundle exec rake` + `pnpm build` + `pnpm test`).
- Lint: `bin/lint` (`rubocop` + `pnpm lint` + `pnpm typecheck`). Auto-fix: `bin/format`.
- JS-only aggregate: `cd vite && pnpm run ci`.
- Ruby tests only: `bundle exec rake`. JS tests only: `cd vite && pnpm test`.

### Version sync gotcha

The gem version in `lib/react_email_rails/version.rb` is the source of truth, and the renderer protocol in `lib/react_email_rails/render_protocol.rb` is synced into the Vite package. After changing either, run `cd vite && pnpm run sync:version`, or `scripts/check_version_sync.rb` / `bin/test` will fail.

### Exercising the renderer manually (optional)

The Node renderer speaks a JSON-over-stdio protocol (this is what the gem invokes). After `cd vite && pnpm build`, from a project that has a `vite.config` using `reactEmailRails()` and email components under `app/javascript/emails/`:

- Health check: `node <repo>/vite/bin/dev.mjs --health` → `{"ok":true,"protocolVersion":...}`.
- Render: pipe `{"component":"<mailer>/<action>","props":{...}}` into `node <repo>/vite/bin/dev.mjs`; it returns `{ "html": ..., "text": ... }`.
