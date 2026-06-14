![react-email-rails](react-email-rails.png)

# react-email-rails

Build and send emails using React and Rails with [React Email](https://react.email) and [Action Mailer](https://guides.rubyonrails.org/action_mailer_basics.html).

## Contents

- [Why](#why)
- [How](#how)
- [Status](#status)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Development](#development)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Why

Building HTML emails is painfully archaic. [React Email](https://react.email) brings React, Tailwind, and TypeScript to email templates. This gem wires it into Action Mailer so React components deliver as generated HTML and text emails.

## How

**In development,** the gem renders components live through Vite's dev pipeline, so your emails get the same module resolution and transforms as the rest of your frontend.

**In production,** Rails builds a server-side renderer bundle during `assets:precompile` using `reactEmailRails()` in your Vite config for discovery and options.

react-email-rails automatically renders both HTML and plain-text versions from the same component. Delivery, headers, previews, queues, and callbacks all stay normal Action Mailer. If rendering fails, no email is sent and `ReactEmailRails::RenderError` is raised.

## Status

**react-email-rails is pre-1.0.** It was extracted from [XOXO](https://xoxo.email) which is pre-launch, so it hasn't been battle-tested in high-volume production environments yet. It's tested in CI across the supported Ruby, Rails, Node, and Vite versions, but the API may still change before 1.0. Please [share feedback and report issues](https://github.com/heysupertape/react-email-rails/issues).

## Requirements

- Ruby >= 3.3
- Action Mailer, Active Support, and Railties >= 7.1 and < 9.0
- Node >= 20.19
- Vite 7 or 8
- React 18 or 19
- `@react-email/render` 2.x

> We recommend [rails_vite](https://github.com/skryukov/rails_vite/) for Vite with Rails.

## Quick Start

Add the gem:

```ruby
# Gemfile

gem "react-email-rails"
```

### Automatic Install

Run the installer:

```sh
bin/rails generate react_email_rails:install
```

This creates `config/initializers/react_email_rails.rb`, installs missing JavaScript dependencies when it can detect your package manager, adds `reactEmailRails()` to `vite.config.*`, and creates `app/javascript/emails`.

The installed setup then follows the normal Rails lifecycle:

- `bin/rails generate react_email_rails:email ...` creates matching mailers and React components.
- `bin/dev` renders through Vite on demand.
- `bin/rails assets:precompile` builds the production renderer bundle automatically.
- `bin/rails react_email_rails:build` builds the bundle directly when CI or tests need it.

### Manual Install

Install the npm package and peer dependencies manually:

```sh
npm i react-email-rails @react-email/render @react-email/components react react-dom
```

Update your Vite config to add the plugin:

```ts
// vite.config.ts

import { defineConfig } from "vite"
import { reactEmailRails } from "react-email-rails"

export default defineConfig({
  plugins: [reactEmailRails()],
})
```

### Your First Email

Generate a mailer and React Email component:

```sh
bin/rails generate react_email_rails:email Account welcome
```

The generator follows Rails' mailer generator shape: `NAME [method method]`. It creates the mailer, matching React components, a mailer preview, and a test. It reads `emails.path` and `emails.extension` from `reactEmailRails()` when available. Pass flags to override them:

```sh
bin/rails generate react_email_rails:email Account welcome --emails-path=app/emails --extension=jsx
```

Edit the generated mailer to pass any necessary props:

```ruby
class AccountMailer < ApplicationMailer
  def welcome
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

Edit the generated email component:

```tsx
// app/javascript/emails/account_mailer/welcome.tsx

import { Body, Container, Html, Text } from "@react-email/components"

type WelcomeProps = {
  account: {
    name: string
  }
}

export default function Welcome({ account }: WelcomeProps) {
  return (
    <Html>
      <Body>
        <Container>
          <Text>Welcome, {account.name}</Text>
        </Container>
      </Body>
    </Html>
  )
}
```

> [@react-email/components](https://react.email/docs/components/html) provides primitives like `<Button>`, `<Heading>`, `<Tailwind>`, and more.

That's it. It now renders and delivers like any other Action Mailer email.

## Usage

Pass data from your mailer and each top-level key becomes a prop on the component's default export. Our API mirrors [inertia-rails](https://inertia-rails.dev), making the two libraries feel consistent when used together.

```ruby
mail react: { foo: "bar" }, ...
```

```tsx
export default function Email({ foo }: { foo: string }) {
  // ...
}
```

### Props

Choose the level of inference you want for your props:

#### Implicit Component, Instance Props

```ruby
class AccountMailer < ApplicationMailer
  use_react_instance_props

  def welcome
    @account = params.fetch(:account)
    mail react: true, to: @account.email, subject: "Welcome"
  end
end
```

Action Mailer's framework assigns (including `params` and `rendered_format`) are excluded from instance props.

Without `use_react_instance_props`, `react: true` still infers the component and renders it with no props, which is handy for emails that take no props at all.

#### Implicit Component, Explicit Props

```ruby
mail(
  ...
  react: {
    account: {
      name: account.name,
    },
  },
)
```

#### Explicit Component, Explicit Props

```ruby
mail(
  ...
  react: "accounts/welcome",
  props: {
    account: {
      name: account.name,
    },
  },
)
```

### Shared Props

Use `react_email_share` to share data with all of a mailer's emails and subclasses, and it'll be automatically merged with any inline props.

```ruby
class MarketingMailer < ApplicationMailer
  # Static value
  react_email_share app_name: "Acme"

  # Lambda value, evaluated lazily in the mailer instance
  react_email_share unread_count: -> { current_user&.unread_count }

  # Block, evaluated lazily in the mailer instance
  react_email_share do
    { brand: { name: "Acme", url: marketing_url } }
  end
end
```

Per-mail props win over shared props of the same name, so a mailer can always override what it inherits:

```ruby
mail react: { app_name: "Acme Pro" }, ... # overrides the shared app_name
```

Shared props apply to all three forms above (`react:` hash, `react: "component", props:`, and `react: true`).

#### Conditional Sharing

Pass any `before_action` filter (`only`, `except`, `if`, `unless`) to scope a share to certain actions:

```ruby
react_email_share only: [:welcome, :reactivation] do
  { promotion: current_promotion }
end

react_email_share if: :user_signed_in? do
  { user: { name: current_user.name } }
end
```

You can also share from inside an action, before calling `mail`:

```ruby
def welcome
  react_email_share notice: "Thanks for joining!"
  mail react: { account: }, to: account.email, subject: "Welcome"
end
```

#### Deep Merging

By default shared props are merged shallowly, so a per-mail prop replaces a shared one of the same name outright. Pass `deep_merge: true` to merge nested hashes instead:

```ruby
react_email_share do
  { settings: { theme: "light", locale: "en" } }
end

# Shallow (default): settings => { theme: "dark" }
mail react: { settings: { theme: "dark" } }, ...

# Deep: settings => { theme: "dark", locale: "en" }
mail react: { settings: { theme: "dark" } }, deep_merge: true, ...
```

Set `config.deep_merge_shared_props = true` to make deep merging the default for every email. (See [Configuration](#configuration))

### Prop Serialization

Like `render json:`, `mail react:` accepts any object that responds to `as_json`, including hashes, Active Model objects, and serializers such as [Alba](https://github.com/okuramasafumi/alba) or [ActiveModel::Serializer](https://github.com/rails-api/active_model_serializers).

### Prop Transformation

Prop keys are camelized by default, so `account.plan_name` arrives as `account.planName`. Override `transform_props` in your [configuration](#configuration).

### Component Names

Component names are inferred from the mailer and action:

| Mailer action | Component |
|---------------|-----------|
| `AccountMailer#welcome` | `account_mailer/welcome` |
| `Users::InviteMailer#new_invite` | `users/invite_mailer/new_invite` |

Rails derives `account_mailer` from `AccountMailer` via `mailer_name`. By default, `account_mailer/welcome` resolves to `app/javascript/emails/account_mailer/welcome.tsx` or `.jsx`.

Files and directories starting with `_` are ignored as renderable email entries by default. Use them for shared components such as `_components/email_layout.tsx`. They can still be imported by email components.

Override the inferred name per mail:

```ruby
mail react: "users/welcome", props: { user: }, to:, subject:
```

Or override `component_path_resolver` globally in your [configuration](#configuration).

### Layouts

Action Mailer layouts aren't applied to `react:` emails. React Email treats layouts like any other component, so share structure with normal React composition instead:

```tsx
// app/javascript/emails/_components/email_layout.tsx

import { Body, Container, Html } from "@react-email/components"
import type { ReactNode } from "react"

type EmailLayoutProps = {
  children: ReactNode
}

export function EmailLayout({ children }: EmailLayoutProps) {
  return (
    <Html>
      <Body>
        <Container>{children}</Container>
      </Body>
    </Html>
  )
}
```

```tsx
// app/javascript/emails/account_mailer/welcome.tsx

import { Text } from "@react-email/components"
import { EmailLayout } from "../_components/email_layout"

export default function Welcome() {
  return (
    <EmailLayout>
      <Text>Welcome</Text>
    </EmailLayout>
  )
}
```

See [Component Names](#component-names) for how shared `_` files are handled.

### Editor

If you're also using [@react-email/editor](https://react.email/docs/editor) to let users compose emails inside your app, `ReactEmailRails.compose` can render those stored documents on the server.

See [Editor rendering](docs/editor.md) for setup and usage.

## Configuration

Configuration is handled primarily on the Rails side, though there are some Vite options to be aware of.

### Rails Configuration

If the defaults don't fit, override them in `config/initializers/react_email_rails.rb`:

| Option | Default |
|--------|---------|
| `component_path_resolver` | `->(mailer:, action:) { "#{mailer}/#{action}" }` |
| `transform_props` | `:lower_camel` |
| `render_mode` | `:subprocess` |
| `render_options` | `{}` |
| `render_timeout` | `10` seconds |
| `render_process_max_requests` | `1_000` |
| `on_render_error` | `nil` |
| `deep_merge_shared_props` | `false` |

#### Prop Transformation

Set `transform_props` to another supported value if you prefer a different prop key style:

| Value | Example |
|-------|---------|
| `:camel` | `AccountName` |
| `:lower_camel` (default) | `accountName` |
| `:dash` | `account-name` |
| `:snake` | `account_name` |
| `:none` | preserves serialized keys |

```ruby
ReactEmailRails.configure do |config|
  config.transform_props = :none
end
```

`transform_props` only controls prop key names. Props are always serialized with `as_json`.

#### Render Modes

`:subprocess` starts a fresh Node process for each render. It's simple, isolated, and always uses the latest bundle, but pays Node startup and bundle load each time.

`:persistent` reuses one long-lived Node process per worker. It's faster for render-heavy workers, but uses more memory and can serve a stale component until recycled. The default `:subprocess` mode is usually enough. Switch when Node startup shows up in traces or batch jobs render many emails from the same bundle.

Enable persistent mode for render-heavy worker processes:

```ruby
ReactEmailRails.configure do |config|
  config.render_mode = :persistent
end
```

Persistent mode keeps one Node child per process:

- Renders are newline-delimited JSON and processed one at a time. Scale throughput with more worker processes.
- It's fork-safe: under clustered Puma or forking job runners, each worker spawns its own child.
- The child is recycled after `render_process_max_requests` renders to bound memory growth. Set it to `nil` to disable recycling.

#### Render Options

`render_options` is passed to [@react-email/render](https://react.email/docs/utilities/render). Use `html` and `text` keys for each output. Option keys are camelized before they cross into JavaScript.

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

#### Error Reporting

Use `on_render_error` to report failures before the exception is re-raised. The callback receives the error plus `kind:` and `component:`:

```ruby
ReactEmailRails.configure do |config|
  config.on_render_error = ->(error, **context) {
    Rails.error.report(error, context:)
  }
end
```

#### Instrumentation

Every render emits `render.react-email-rails` through [ActiveSupport::Notifications](https://guides.rubyonrails.org/active_support_instrumentation.html). The payload includes `kind`, `component`, and successful HTML size in `html_bytes`:

```ruby
ActiveSupport::Notifications.subscribe("render.react-email-rails") do |event|
  Rails.logger.info("[react-email-rails] Rendered #{event.payload[:component]} (Duration: #{event.duration.round}ms | Size: #{event.payload[:html_bytes]} bytes)")
end
```

### Vite Configuration

Most apps only need the `reactEmailRails()` plugin from [Quick Start](#quick-start). The options below change component discovery, bundle dependency handling, and isolated renderer transforms.

In development and production, the isolated renderer loads `reactEmailRails()`, JSX support, and component-facing Vite config such as `resolve`, `define`, `css`, `json`, `assetsInclude`, `esbuild`, and `oxc`. It doesn't load your other app plugins. Server, preview, dependency optimization, and build output settings stay owned by react-email-rails.

#### Plugin Options

| Option | Default | Description |
|--------|---------|-------------|
| `emails.path` | `"app/javascript/emails"` | Directory containing email components |
| `emails.extension` | `[".tsx", ".jsx"]` | Component extension, or an array of extensions |
| `emails.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `emails.path` |
| `standalone` | `true` | Inline production renderer bundle dependencies |
| `vite` | `{}` | Extra email-only Vite config for compilation and resolution |

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

Component names come from the Vite directory layout (see [Component Names](#component-names)). To map mailer actions to a different layout, override `component_path_resolver` on the Ruby side rather than renaming in the plugin, so both halves stay in sync.

#### Advanced: Email-Only Vite Plugins

Most apps don't need extra email plugins. If email components need a transform that isn't part of Vite's default pipeline, add that transform to the isolated renderer:

```ts
import mdx from "@mdx-js/rollup"
import { defineConfig } from "vite"
import { reactEmailRails } from "react-email-rails"

export default defineConfig({
  plugins: [
    reactEmailRails({
      vite: {
        plugins: [mdx()],
      },
    }),
  ],
})
```

These `vite` options are used by `react-email-rails-dev` and `react-email-rails-build`. Only `assetsInclude`, `css`, `define`, `esbuild`, `json`, `oxc`, `plugins`, and `resolve` are accepted. Output settings such as `build.outDir` and `build.rollupOptions` are ignored so Ruby can always find the bundle.

#### Standalone Builds

By default the production renderer bundle inlines React, `@react-email/render`, and other Node dependencies. This works well for Rails deploys that build assets in one stage and run without `node_modules` in the final image. Development previews keep dependencies external, even when `standalone` is enabled.

Set `standalone: false` when your runtime already ships `node_modules` and you prefer a smaller SSR-style bundle:

```ts
reactEmailRails({
  standalone: false,
})
```

Externalized bundles are smaller and may build faster, but the renderer needs the externalized packages available at runtime.

## Deployment

For production deploys, run the normal Rails asset task:

```sh
bin/rails assets:precompile
```

The `react_email_rails:build` task is hooked into `assets:precompile` automatically. It loads `reactEmailRails()` options from your Vite config, then writes `tmp/react-email-rails/emails.js` with the email component registry. If [Editor document rendering](docs/editor.md) is enabled, the bundle also includes document renderers.

You can run it directly when needed:

```sh
bin/rails react_email_rails:build
```

Production rendering runs that bundle with Node. Set `SKIP_REACT_EMAIL_RAILS_BUILD=1` to skip the automatic asset hook. Directly running `bin/rails react_email_rails:build` always attempts the build.

The npm package, Vite, React, and `@react-email/render` must be available when Rails runs `assets:precompile`. If you enable [Editor document rendering](docs/editor.md), its peer dependencies must be available too.

The bundle is required, not an optimization. If it's missing, renders raise `ReactEmailRails::RenderError`. Action Mailer deliveries aren't sent.

The Ruby gem and npm package must stay on the same version. The renderer includes a small protocol/version handshake, so mismatched installs fail with an actionable `ReactEmailRails::RenderError` instead of silently returning malformed output.

The build command preserves `emails.path`, `emails.extension`, `emails.ignore`, `standalone`, and email-only `vite` options.

### Renderer Verification

To confirm the renderer is ready before relying on it, run:

```sh
bin/rails react_email_rails:verify
```

It checks that the render command runs and that the npm package version matches the gem, then exits non-zero with an actionable message on failure. Wire it into CI or release steps to catch missing bundles or version drift before the first render.

For programmatic checks (for example, a health endpoint), `ReactEmailRails.healthy?` returns a boolean. If you specifically want a check at boot, call it from your own initializer and scope it to the processes that send mail so others don't pay the cost:

```ruby
Rails.application.config.after_initialize do
  if Rails.env.production? && Sidekiq.server? && !ReactEmailRails.healthy?
    Rails.logger.error("[react-email-rails] renderer verification failed")
  end
end
```

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, checks, formatting, and release verification.

## Contributing

Bug reports and pull requests are welcome on GitHub. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Security

Please report vulnerabilities privately. See [SECURITY.md](SECURITY.md) for details.

## License

The gem and npm package are available as open source under the terms of the [MIT License](LICENSE.md).
