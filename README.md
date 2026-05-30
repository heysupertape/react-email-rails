# react-email-rails

Send emails using [React Email](https://react.email) components from Rails with Action Mailer.

The Ruby gem handles mailer integration, props, caching, health checks, and process management. The companion npm package provides a Vite plugin and render runtime.

## How It Works

**Development:** the gem renders components through Vite's dev pipeline, so email components can use the same module resolution and transforms as the rest of your frontend code. The dev renderer loads only the `reactEmailRails()` plugin plus your `resolve`, `define`, and `css` config — not the rest of your dev-server plugins — so an email that relies on other plugins may behave differently than under `vite build --mode email`. The default `:subprocess` mode boots a fresh dev server per render, which always picks up your latest edits; `:persistent` mode reuses the dev server and is faster but can serve a stale component until the process is recycled.

**Production:** Vite builds a server-side email bundle ahead of time. The gem runs that bundle with Node, sends props to the requested component, and receives rendered HTML and plain text.

Delivery, headers, multipart parts, previews, queues, and callbacks stay normal Action Mailer. If rendering fails, the mail fails closed with `ReactEmailRails::RenderError`.

## Quick Start

Add the gem:

```ruby
# Gemfile
gem "react-email-rails"
```

Install the npm package and peer dependencies:

```sh
pnpm add react-email-rails @react-email/render react react-dom
```

This package assumes your Rails app already has Vite. If you are adding Vite to a Rails app from scratch, we recommend [rails_vite](https://github.com/skryukov/rails_vite/) as the Rails/Vite integration.

Install the optional initializer:

```sh
bin/rails generate react_email_rails:install
```

Add the Vite plugin:

```ts
// vite.config.ts
import { defineConfig } from "vite"
import { reactEmailRails } from "react-email-rails"

export default defineConfig({
  plugins: [reactEmailRails()],
})
```

Create an email component:

```tsx
// app/javascript/emails/account_mailer/created.tsx
type CreatedProps = {
  account: {
    name: string
  }
}

export default function Created({ account }: CreatedProps) {
  return (
    <html>
      <body>
        <p>Welcome to {account.name}</p>
      </body>
    </html>
  )
}
```

Render it from a mailer:

```ruby
class AccountMailer < ApplicationMailer
  def created
    account = params.fetch(:account)

    mail(
      react: {
        account: {
          name: account.name,
        },
      },
      to: account.email,
      subject: "Welcome",
    )
  end
end
```

Build the render bundle outside development:

```sh
vite build --mode email
```

## Usage

`react:` accepts three forms:

```ruby
mail react: { user: }, to:, subject:               # infer component, explicit props
mail react: "users/welcome", props: { user: }, ... # explicit component + props
mail react: true, to:, subject:                     # infer component + instance props
```

### Component Names

By default, component names are inferred from the mailer and action:

| Mailer action | Component |
|---------------|-----------|
| `AccountMailer#created` | `account_mailer/created` |
| `Users::InviteMailer#new_invite` | `users/invite_mailer/new_invite` |

The default Vite plugin path resolves those names under `app/javascript/emails`, so `account_mailer/created` maps to `app/javascript/emails/account_mailer/created.tsx` or `app/javascript/emails/account_mailer/created.jsx`.

Override the inferred name per mail:

```ruby
mail react: "users/welcome", props: { user: }, to:, subject:
```

Or override the resolver globally:

```ruby
ReactEmailRails.configure do |config|
  config.component_path_resolver = ->(mailer:, action:) { "#{mailer}/#{action}" }
end
```

### Props

Explicit props are serialized with `as_json`, recursively camelized, and sent to React:

```ruby
mail react: {
  account: {
    name: account.name,
    plan_name: account.plan.name,
  },
}, to:, subject:
```

Plain Hashes work well, and so does any object that responds to `as_json`. That includes Active Model objects and serialization libraries like [Alba](https://github.com/okuramasafumi/alba). For TypeScript props, we recommend generating shared Ruby-to-TypeScript types with [Typelizer](https://github.com/jetrockets/typelizer).

Use `props:` when passing an explicit component name:

```ruby
mail react: "accounts/welcome", props: {
  account: {
    name: account.name,
  },
}, to:, subject:
```

Use `react: true` to send mailer instance variables as props:

```ruby
class AccountMailer < ApplicationMailer
  use_react_instance_props

  def created
    @account = params.fetch(:account)
    mail react: true, to: @account.email, subject: "Welcome"
  end
end
```

Framework internals and `params` are excluded from instance props. Without `use_react_instance_props`, `react: true` still infers the component and renders it with no props, which is handy for emails that take no props at all.

### Render Options

`render_options` is passed to [`@react-email/render`](https://react.email/docs/utilities/render). `html` options are used for HTML rendering and `text` options are used for plain-text rendering. Keys are camelized before they cross into JavaScript.

```ruby
ReactEmailRails.configure do |config|
  config.render_options = {
    html: {
      pretty: Rails.env.development?
    },
    text: {
      html_to_text_options: {
        selectors: [{ selector: "img", format: "skip" }],
      },
    },
  }
end
```

## Vite Config

The default plugin config discovers `.tsx` and `.jsx` files in `app/javascript/emails` and builds the email SSR bundle only when Vite runs in `email` mode:

```ts
import { defineConfig } from "vite"
import { reactEmailRails } from "react-email-rails"

export default defineConfig({
  plugins: [reactEmailRails()],
})
```

### Plugin Options

| Option | Default | Description |
|--------|---------|-------------|
| `emails.path` | `"app/javascript/emails"` | Directory containing email components |
| `emails.extension` | `[".tsx", ".jsx"]` | Component extension, or an array of extensions |
| `emails.lazy` | `true` | Use lazy `import.meta.glob` entries |
| `emails.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `emails.path` |
| `standalone` | `false` | Inline SSR dependencies with `ssr.noExternal: true` |

Component names come from the Vite directory layout (see [Component Names](#component-names)). To map mailer actions to a different layout, override `component_path_resolver` on the Ruby side rather than rewriting names in the plugin, so both halves stay in sync.

Use a custom directory:

```ts
reactEmailRails({
  emails: "app/emails",
})
```

Use multiple extensions:

```ts
reactEmailRails({
  emails: {
    extension: [".email.tsx", ".email.jsx"],
  },
})
```

Prefer eager imports in production persistent renderers so component import failures happen during boot health checks:

```ts
reactEmailRails({
  emails: {
    lazy: false,
  },
})
```

## Configuration

The defaults fit the standard companion-package setup, so most apps configure nothing. Every option is overridable via `ReactEmailRails.configure`.

| Option | Default |
|--------|---------|
| `render_command` | dev: `["node_modules/.bin/react-email-rails-dev"]`; else `["node", "tmp/react-email-rails/emails.js"]` |
| `render_timeout` | `10` seconds |
| `cache` | `ActionMailer::Base.perform_caching` |
| `cache_version` | digest of `tmp/react-email-rails/emails.js` |
| `cache_store` | `Rails.cache` |
| `component_path_resolver` | `->(mailer:, action:) { "#{mailer}/#{action}" }` |
| `prop_serializer` | `->(props:) { props.as_json }` |
| `prop_transformer` | recursive camelCase |
| `render_mode` | `:subprocess` |
| `render_options` | `{}` |
| `render_process_max_requests` | `1_000` |
| `on_render_error` | `nil` |
| `verify_render_on_boot` | `-> { Rails.env.production? }` |

Custom `render_command` values should be argv arrays, for example `["node", Rails.root.join("tmp/react-email-rails/emails.js").to_s]`, and must follow the same JSON stdin/stdout contract as the bundled render runtime.

### Custom Render Commands

Most apps should use the bundled renderer. If you provide a custom `render_command`, the command must read JSON from stdin and write JSON to stdout. Stderr is treated as diagnostic output and may be included in raised `ReactEmailRails::RenderError` messages.

In `:subprocess` mode, each render starts a fresh process. The request body is:

```json
{
  "component": "account_mailer/created",
  "props": { "accountName": "Ada" },
  "renderOptions": {
    "html": { "pretty": true },
    "text": {}
  }
}
```

Successful responses must include HTML and may include text:

```json
{
  "html": "<p>Hello Ada</p>",
  "text": "Hello Ada"
}
```

For health checks, the command is called with `--health` and should write:

```json
{ "ok": true }
```

In `:persistent` mode, the command is called with `--persistent`. It receives newline-delimited JSON requests and must write one newline-terminated JSON response per request. Render responses should include `ok: true`:

```json
{ "ok": true, "html": "<p>Hello Ada</p>", "text": "Hello Ada" }
```

Persistent health checks are sent over the same stdin/stdout protocol:

```json
{ "health": true }
```

and should return:

```json
{ "ok": true }
```

Persistent failures should return `ok: false` with an error string. The response line must be complete before `render_timeout`; partial lines are treated as timeouts.

### Caching

`cache` can be `false`, `true`, a Hash, or a callable. Callable cache settings are evaluated in the mailer instance, so caching can vary by action.

`cache_version` defaults to a digest of the built email bundle. Deploys do not serve stale HTML after component changes as long as the bundle changes.

### Render Modes

| Mode | Pros | Cons |
|------|------|------|
| `:subprocess` | Simple isolation; every render starts fresh; easiest failure recovery | Starts Node and loads the bundle for every render |
| `:persistent` | Reuses one Node process; avoids repeated startup and bundle load cost | More moving parts; long-lived process can hold memory or stale module state until recycled |

Prefer delivering mail through background jobs so render latency does not sit in the request path. With that setup, the default `:subprocess` mode is usually acceptable for lighter workloads, previews, and apps where email render latency is not a bottleneck.

Switch to `:persistent` when mail rendering happens in hot worker paths, Node startup time shows up in traces, or a batch job renders many emails with the same bundle. Keep `:subprocess` when renders are rare, when process isolation matters more than latency, or while you are still validating a new production setup.

Use `:persistent` for render-heavy worker processes:

```ruby
ReactEmailRails.configure do |config|
  config.render_mode = :persistent
  config.render_process_max_requests = 1_000
end
```

Persistent mode keeps one child process alive and sends newline-delimited JSON requests to it. The child is recycled after `render_process_max_requests` to bound memory growth. Set `render_process_max_requests` to `nil` to disable recycling.

Each process keeps its own child, and renders through that child are serialized one at a time. Scale by running more worker processes, not by expecting one persistent child to render concurrently. The child is tied to the process that spawned it: forked workers each start their own, so it is safe under clustered Puma or forking job runners.

### Error Reporting

Use `on_render_error` to report failures before the exception is re-raised:

```ruby
ReactEmailRails.configure do |config|
  config.on_render_error = ->(error, component:) {
    Rails.error.report(error, context: { component: })
  }
end
```

## Deployment

Build the email render bundle on every process that renders mail:

```sh
vite build --mode email
```

By default the bundle externalizes `react`, `react-dom`, `@react-email/render`, and the runtime, so the renderer needs `node_modules` present alongside `tmp/react-email-rails/emails.js` at runtime. If you deploy the bundle without `node_modules`, set `standalone: true` on the plugin to inline those dependencies into a self-contained bundle.

Prefer `deliver_later` for production mail so rendering and delivery happen in a background job. If your web process never renders mail directly, for example all mail uses `deliver_later` and Sidekiq performs delivery, build the bundle only for the worker process.

Scope boot verification the same way:

```ruby
ReactEmailRails.configure do |config|
  config.verify_render_on_boot = -> { Rails.env.production? && Sidekiq.server? }
  config.render_mode = :persistent if Rails.env.production? && Sidekiq.server?
end
```

Keep the bundle on any process that calls `deliver_now`, renders previews in production, or otherwise builds Action Mailer messages synchronously.

## Using with Inertia Rails

`react-email-rails` was heavily influenced by `inertia-rails` and is designed to feel like a seamless companion to it. Mailers use the same React component and props vocabulary as the rest of an Inertia Rails app, while staying inside Action Mailer's delivery, preview, callback, and multipart conventions.

By default, props are serialized with `as_json` and recursively camelized before they reach React. That matches the shape many Inertia Rails apps already use for page props, so serializers and frontend component conventions can usually be shared between web pages and email components.

## Requirements

- Ruby >= 3.3
- Action Mailer, Active Support, and Railties >= 7.1 and < 9.0
- Node >= 20
- Vite 7 or 8
- React 18 or 19
- `@react-email/render` 2.x

CI tests Ruby 3.3, 3.4, and 4.0 against Rails 7.2, Rails 8.0, and the latest supported Rails components. It also tests Node 20.19, 22, and 24 against Vite 7 and 8.

## Development

Install dependencies:

```sh
bundle install
cd vite && pnpm install
```

Run checks:

```sh
ruby scripts/check_version_sync.rb
bin/test
bin/lint
cd vite && pnpm run build
```

Format Ruby and TypeScript/JavaScript code:

```sh
bin/format
```

Build release artifacts:

```sh
bundle exec rake build
cd vite && pnpm pack --dry-run
```

The Ruby gem version in `lib/react_email_rails/version.rb` is the source of truth. The npm package still needs a literal `version` in `vite/package.json`, so `cd vite && pnpm pack` syncs that field from the Ruby version before building.

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem and npm package are available as open source under the terms of the [MIT License](LICENSE.md).
