# Rails + React Email

Build and send emails using React and Rails — a seamless integration between [React Email](https://react.email) and [Action Mailer](https://guides.rubyonrails.org/action_mailer_basics.html).

## Contents

- [Why?](#why)
- [How?](#how)
- [Status](#status)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Why?

Building HTML emails is painfully archaic. [React Email](https://react.email) is a collection of unstyled components for building emails with React, Tailwind, and TypeScript. This gem brings that power directly into your Rails app: write emails as React components and send them through Action Mailer.

## How?

**In development,** the gem renders components live through Vite's dev pipeline, so your emails get the same module resolution and transforms as the rest of your frontend. No build step needed — each render picks up your latest edits.

**In production,** Vite builds a server-side email bundle ahead of time (`vite build --mode email`). The gem runs that bundle with Node, sends props to the requested component, and receives rendered HTML and plain text back.

Delivery, headers, multipart parts, previews, queues, and callbacks all stay normal Action Mailer. If rendering fails, no email is sent and `ReactEmailRails::RenderError` is raised.

The dev renderer loads the `reactEmailRails()` plugin, JSX support, and your `resolve`, `define`, and `css` config — but none of your other dev-server plugins.

> `react-email-rails` was heavily influenced by [`inertia-rails`](https://inertia-rails.dev) and is designed as a companion to it. Mailers use the same component and props vocabulary as an Inertia Rails app, while staying inside Action Mailer's conventions.

## Status

**`react-email-rails` is pre-1.0.** It's tested in CI across the supported Ruby, Rails, Node, and Vite versions, but it hasn't been battle-tested in high-volume production environments yet, and the API may still change before 1.0. Give it a try, and please [share feedback and report issues](https://github.com/heysupertape/react-email-rails/issues) so we can keep hardening it toward a stable release.

## Requirements

- Ruby >= 3.3
- Action Mailer, Active Support, and Railties >= 7.1 and < 9.0
- Node >= 20.19
- Vite 7 or 8
- React 18 or 19
- `@react-email/render` 2.x

> [`rails_vite`](https://github.com/skryukov/rails_vite/) is our recommended way to use Vite with Rails.

## Quick Start

Add the gem:

```ruby
# Gemfile
gem "react-email-rails"
```

Optionally, generate an initializer to customize behavior later:

```sh
bin/rails generate react_email_rails:install
```

Install the npm package and its peer dependencies:

```sh
npm i react-email-rails @react-email/render @react-email/components react react-dom
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
import { Body, Container, Html, Text } from "@react-email/components"

type CreatedProps = {
  account: {
    name: string
  }
}

export default function Created({ account }: CreatedProps) {
  return (
    <Html>
      <Body>
        <Container>
          <Text>Welcome to {account.name}</Text>
        </Container>
      </Body>
    </Html>
  )
}
```

> [`@react-email/components`](https://react.email/docs/components/html) provides the full set of email-tested primitives — `<Button>`, `<Heading>`, `<Tailwind>`, and more.

Render it from a mailer:

```ruby
class AccountMailer < ApplicationMailer
  def created
    account = params.fetch(:account)

    mail(
      to: account.email,
      subject: "Welcome",
      react: {
        account: {
          name: account.name,
        },
      },
    )
  end
end
```

That's it — it now delivers like any other Action Mailer message. In development it renders live; for production, you'll build the email bundle first (see [Deployment](#deployment)).

## Usage

Inside a mailer, `react:` accepts three forms:

| Type | Example | Component | Props |
|------|---------|-----------|-------|
| `Hash` | `react: { account: }` | inferred from mailer + action | the hash |
| `String` | `react: "accounts/welcome", props: { account: }` | the string | `props:` (optional) |
| `true` | `react: true` | inferred from mailer + action | instance variables with `use_react_instance_props`, otherwise none |

Each top-level key you pass becomes a prop on the component's default export — `react: { account: }` renders `Created` with an `account` prop.

### Component Names

By default, component names are inferred from the mailer and action:

| Mailer action | Component |
|---------------|-----------|
| `AccountMailer#created` | `account_mailer/created` |
| `Users::InviteMailer#new_invite` | `users/invite_mailer/new_invite` |

Rails derives `account_mailer` from `AccountMailer` via its `mailer_name`. The default Vite plugin resolves those names under `app/javascript/emails`, so `account_mailer/created` maps to `app/javascript/emails/account_mailer/created.tsx` or `.jsx`.

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

Keys are camelized on the way to React, so `plan_name` arrives as `account.planName` in your component.

Just like `render json:` in controllers, you can pass any object that responds to `as_json` — plain hashes, Active Model objects, and serialization libraries like [Alba](https://github.com/okuramasafumi/alba) or [ActiveModel::Serializer](https://github.com/rails-api/active_model_serializers). For TypeScript props, we recommend generating them with [Typelizer](https://typelizer.dev).

Use `props:` when passing an explicit component name:

```ruby
mail react: "accounts/welcome", props: {
  account: {
    name: account.name,
  },
}, to:, subject:
```

Use `react: true` to send the mailer's instance variables as props:

```ruby
class AccountMailer < ApplicationMailer
  use_react_instance_props

  def created
    @account = params.fetch(:account)
    mail react: true, to: @account.email, subject: "Welcome"
  end
end
```

Action Mailer's framework assigns (including `params` and `rendered_format`) are excluded from instance props. Without `use_react_instance_props`, `react: true` still infers the component and renders it with no props, which is handy for emails that take no props at all.

### Render Options

`render_options` is passed to [`@react-email/render`](https://react.email/docs/utilities/render). `html` options apply to HTML rendering and `text` options apply to plain-text rendering. Keys are camelized before they cross into JavaScript.

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

## Configuration

Configuration is handled primarily on the Rails side, though there are some Vite options to be aware of.

### Rails Configuration

The defaults fit a standard install, so most apps configure nothing. Every option is overridable via `ReactEmailRails.configure` in your initializer.

| Option | Default |
|--------|---------|
| `cache` | `ActionMailer::Base.perform_caching` |
| `cache_version` | digest of `tmp/react-email-rails/emails.js` |
| `cache_store` | `Rails.cache` |
| `component_path_resolver` | `->(mailer:, action:) { "#{mailer}/#{action}" }` |
| `prop_serializer` | `->(props:) { props.as_json }` |
| `prop_transformer` | recursive camelCase |
| `render_mode` | `:subprocess` |
| `render_options` | `{}` |
| `render_command` | dev: `["node_modules/.bin/react-email-rails-dev"]`; else `["node", "tmp/react-email-rails/emails.js"]` |
| `render_timeout` | `10` seconds |
| `render_process_max_requests` | `1_000` |
| `on_render_error` | `nil` |
| `verify_render_on_boot` | `-> { Rails.env.production? }` |

Paths in the default `render_command` are resolved against `Rails.root`. A custom `render_command` must be an argv array and must follow the JSON contract described in [Custom Render Commands](#custom-render-commands).

#### Caching

`cache` can be `false`, `true`, a Hash, or a callable. Callable cache settings are evaluated in the mailer instance, so caching can vary by action. By default we use `ActionMailer::Base.perform_caching`.

`cache_version` defaults to a digest of the built email bundle. Because the version tracks the bundle's digest, every deploy that changes a component invalidates the cached HTML.

#### Render Modes

| Mode | Description | Pros | Cons |
|------|-------------|------|------|
| `:subprocess` | Starts a fresh Node process for each render | Simple; always uses the latest bundle; failures stay isolated | Slower — pays Node startup and bundle load on every render |
| `:persistent` | Reuses one long-lived Node process per worker | Faster — no per-render startup | Uses more memory; can serve a stale component until recycled |

**When to use which.** Since all mailers should be using [`deliver_later`](https://edgeapi.rubyonrails.org/classes/ActionMailer/MessageDelivery.html#method-i-deliver_later) to send email in a background job anyway, most apps can stay on the default `:subprocess`. Switch to `:persistent` when rendering happens in a hot worker path, Node startup shows up in traces, or a batch job renders many emails from the same bundle (see [Instrumentation](#instrumentation)).

The render mode also shapes the development experience: `:subprocess` boots a fresh Vite dev server per render and always reflects your latest edits, while `:persistent` reuses the server and may serve a stale component until the process is recycled.

Enable persistent mode for render-heavy worker processes:

```ruby
ReactEmailRails.configure do |config|
  config.render_mode = :persistent
  config.render_process_max_requests = 1_000
end
```

Persistent mode keeps one Node child per process:

- Renders are sent as newline-delimited JSON and processed one at a time, so a single child never renders concurrently. Scale throughput by adding worker processes.
- It is fork-safe: under clustered Puma or forking job runners, each worker spawns its own child.
- The child is recycled after `render_process_max_requests` renders to bound memory growth. Set it to `nil` to disable recycling.

#### Error Reporting

Use `on_render_error` to report failures before the exception is re-raised:

```ruby
ReactEmailRails.configure do |config|
  config.on_render_error = ->(error, component:) {
    Rails.error.report(error, context: { component: })
  }
end
```

#### Instrumentation

Every render emits an [`ActiveSupport::Notifications`](https://guides.rubyonrails.org/active_support_instrumentation.html) event named `render.react-email-rails`, so you can log render timing or forward it to your APM. The payload carries the `component` name and, on success, the rendered HTML size in `html_bytes`:

```ruby
ActiveSupport::Notifications.subscribe("render.react-email-rails") do |event|
  Rails.logger.info(
    "[react-email-rails] rendered #{event.payload[:component]} " \
    "(#{event.payload[:html_bytes]} bytes) in #{event.duration.round(1)}ms"
  )
end
```

#### Custom Render Commands

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

In `:persistent` mode, the command is called with `--persistent`. It receives the same request bodies as newline-delimited JSON and must write one newline-terminated JSON response per request. Render responses should include `ok: true`:

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

Persistent failures should return `ok: false` with an error string. Each response must arrive as a complete, newline-terminated line within `render_timeout`; if the deadline passes first, the render times out and any partial output is discarded.

### Vite Configuration

The `reactEmailRails()` plugin (added in [Quick Start](#quick-start)) discovers `.tsx` and `.jsx` files in `app/javascript/emails` and builds the email SSR bundle only when Vite runs in `email` mode. The defaults suit most apps; the options below customize them.

#### Plugin Options

| Option | Default | Description |
|--------|---------|-------------|
| `emails.path` | `"app/javascript/emails"` | Directory containing email components |
| `emails.extension` | `[".tsx", ".jsx"]` | Component extension, or an array of extensions |
| `emails.lazy` | `true` | Use lazy `import.meta.glob` entries |
| `emails.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `emails.path` |
| `standalone` | `false` | Inline SSR dependencies with `ssr.noExternal: true` |

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

Prefer eager imports in production persistent renderers so component import failures surface during boot health checks instead of at render time:

```ts
reactEmailRails({
  emails: {
    lazy: false,
  },
})
```

Component names come from the Vite directory layout (see [Component Names](#component-names)). To map mailer actions to a different layout, override `component_path_resolver` on the Ruby side rather than renaming in the plugin, so both halves stay in sync.

## Deployment

Your normal `vite build` does **not** emit the email bundle — the plugin only produces it in `email` mode. Add a separate build step to your deploy, run on every process that renders mail (in addition to your usual asset build):

```sh
vite build --mode email
```

This writes `tmp/react-email-rails/emails.js`, which the default production `render_command` runs with Node. It's required, not an optimization: if the bundle is missing, renders raise `ReactEmailRails::RenderError` and no mail is sent. (Development needs no build — components render live through Vite.)

By default the bundle externalizes `react`, `react-dom`, `@react-email/render`, and the runtime, so the renderer needs `node_modules` present alongside `tmp/react-email-rails/emails.js` at runtime. To deploy the bundle without `node_modules`, set `standalone: true` on the plugin to inline those dependencies into a self-contained bundle.

Scope boot verification to the same processes that build the bundle:

```ruby
ReactEmailRails.configure do |config|
  config.verify_render_on_boot = -> { Rails.env.production? && Sidekiq.server? }
  config.render_mode = :persistent if Rails.env.production? && Sidekiq.server?
end
```

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
