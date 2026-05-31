# React Email + Rails

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

**In development,** the gem renders components live through Vite's dev pipeline, so your emails get the same module resolution and transforms as the rest of your frontend.

**In production,** Vite builds a server-side email bundle ahead of time. The plugin adds a dedicated `email` build environment, so your normal `vite build` emits the bundle alongside your client assets.

Delivery, headers, multipart parts, previews, queues, and callbacks all stay normal Action Mailer. If rendering fails, no email is sent and `ReactEmailRails::RenderError` is raised.

## Status

**react-email-rails is pre-1.0.** It's tested in CI across the supported Ruby, Rails, Node, and Vite versions, but it hasn't been battle-tested in high-volume production environments yet, and the API may still change before 1.0. Please [share feedback and report issues](https://github.com/heysupertape/react-email-rails/issues).

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
bin/rails generate react_email_rails:email Account created
```

The generator follows Rails' mailer generator shape: `NAME [method method]`. It creates `app/mailers/account_mailer.rb`, matching components under your configured React Email directory, plus a mailer preview and test.

The generator reads `emails.path` and `emails.extension` from `reactEmailRails()` when available. Pass flags to override them:

```sh
bin/rails generate react_email_rails:email Account created --emails-path=app/emails --extension=jsx
```

Edit the generated mailer to pass any necessary props:

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

Edit the generated email component:

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

> [@react-email/components](https://react.email/docs/components/html) provides the full set of primitives — `<Button>`, `<Heading>`, `<Tailwind>`, and more.

That's it — it now renders and delivers like any other Action Mailer email.

## Usage

Pass props with `react:` in your mailers. Each top-level key becomes a prop on the React component's default export.

```ruby
mail react: { foo: "bar" }, ...
```

```tsx
export default function Email({ foo }: { foo: string }) {
  // ...
}
```

Choose the level of inference you want:

### Implicit Component, Instance Props

```ruby
class AccountMailer < ApplicationMailer
  use_react_instance_props

  def created
    @account = params.fetch(:account)
    mail react: true, to: @account.email, subject: "Welcome"
  end
end
```

Action Mailer's framework assigns (including `params` and `rendered_format`) are excluded from instance props.

Without `use_react_instance_props`, `react: true` still infers the component and renders it with no props, which is handy for emails that take no props at all.

### Implicit Component, Explicit Props

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

### Explicit Component, Explicit Props

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

These forms mirror [inertia-rails](https://inertia-rails.dev), making the two libraries feel consistent when used together.

### Component Names

Component names are inferred from the mailer and action:

| Mailer action | Component |
|---------------|-----------|
| `AccountMailer#created` | `account_mailer/created` |
| `Users::InviteMailer#new_invite` | `users/invite_mailer/new_invite` |

Rails derives `account_mailer` from `AccountMailer` via its `mailer_name`. The default Vite plugin resolves those names under `app/javascript/emails`, so `account_mailer/created` maps to `app/javascript/emails/account_mailer/created.tsx` or `.jsx`.

Files and directories starting with `_` are ignored as renderable email entries by default. Use them for shared components such as `_components/email_layout.tsx`; they can still be imported by email components.

Override the inferred name per mail:

```ruby
mail react: "users/welcome", props: { user: }, to:, subject:
```

Or override `component_path_resolver` globally in your [configuration](#configuration).

### Prop Serialization

Just like `render json:` in controllers, you can pass any object that responds to `as_json` to `mail react:`. Plain hashes, Active Model objects, and serialization libraries like [Alba](https://github.com/okuramasafumi/alba) or [ActiveModel::Serializer](https://github.com/rails-api/active_model_serializers) are supported.

### Prop Transformation

By default, prop keys are camelized on the way to React, so `account.plan_name` arrives as `account.planName` in your component. This makes them more idiomatic for the frontend, but you can override the `transform_props` behavior in your [configuration](#configuration).

### Layouts

Action Mailer layouts are not applied to `react:` emails. React Email treats layouts like any other component, so share structure with normal React composition instead:

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
// app/javascript/emails/account_mailer/created.tsx

import { Text } from "@react-email/components"
import { EmailLayout } from "../_components/email_layout"

export default function Created() {
  return (
    <EmailLayout>
      <Text>Welcome</Text>
    </EmailLayout>
  )
}
```

See [Component Names](#component-names) for how shared `_` files are handled.

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
| `on_render_error` | `nil` |
| `verify_render_on_boot` | `false` |

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

`transform_props` only controls prop key names; props are always serialized with `as_json`.

#### Render Modes

`:subprocess` starts a fresh Node process for each render. It's simple, always uses the latest bundle, and keeps failures isolated, but pays Node startup and bundle load on every render.

`:persistent` reuses one long-lived Node process per worker. It's faster because it avoids per-render startup, but uses more memory and can serve a stale component until recycled.

For background email delivery, the default `:subprocess` mode is usually enough. Switch to `:persistent` when Node startup appears in traces or batch jobs render many emails from the same bundle (see [Instrumentation](#instrumentation)).

The render mode also shapes the development experience: `:subprocess` boots a fresh Vite dev server per render and always reflects your latest edits, while `:persistent` reuses the server and may serve a stale component until the process is recycled.

Enable persistent mode for render-heavy worker processes:

```ruby
ReactEmailRails.configure do |config|
  config.render_mode = :persistent
end
```

Persistent mode keeps one Node child per process:

- Renders are sent as newline-delimited JSON and processed one at a time, so a single child never renders concurrently. Scale throughput by adding worker processes.
- It is fork-safe: under clustered Puma or forking job runners, each worker spawns its own child.
- The child is recycled periodically to bound memory growth.

#### Render Options

`render_options` is passed to [@react-email/render](https://react.email/docs/utilities/render). `html` options apply to HTML rendering and `text` options apply to plain-text rendering. Keys are camelized before they cross into JavaScript.

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

Use `on_render_error` to report failures before the exception is re-raised:

```ruby
ReactEmailRails.configure do |config|
  config.on_render_error = ->(error, component:) {
    Rails.error.report(error, context: { component: })
  }
end
```

#### Instrumentation

Every render emits an [ActiveSupport::Notifications](https://guides.rubyonrails.org/active_support_instrumentation.html) event named `render.react-email-rails`, so you can log render timing or forward it to your APM. The payload carries the `component` name and, on success, the rendered HTML size in `html_bytes`:

```ruby
ActiveSupport::Notifications.subscribe("render.react-email-rails") do |event|
  Rails.logger.info(
    "[react-email-rails] rendered #{event.payload[:component]} " \
    "(#{event.payload[:html_bytes]} bytes) in #{event.duration.round(1)}ms"
  )
end
```

### Vite Configuration

Most apps only need the `reactEmailRails()` plugin from [Quick Start](#quick-start). The options below change where components are discovered and how the bundle handles dependencies.

In development, the renderer loads the `reactEmailRails()` plugin, JSX support, and your `resolve`, `define`, and `css` config — but none of your other dev-server plugins.

#### Plugin Options

| Option | Default | Description |
|--------|---------|-------------|
| `emails.path` | `"app/javascript/emails"` | Directory containing email components |
| `emails.extension` | `[".tsx", ".jsx"]` | Component extension, or an array of extensions |
| `emails.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `emails.path` |
| `standalone` | `true` | Inline SSR dependencies with `ssr.noExternal: true` |

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

#### Standalone Builds

By default the email bundle inlines React, `@react-email/render`, and other Node dependencies. That makes the bundle larger, but it works well for Rails deploys that build assets in one stage and run without `node_modules` in the final runtime image.

Set `standalone: false` when your runtime already ships `node_modules` and you prefer a smaller SSR-style bundle:

```ts
reactEmailRails({
  standalone: false,
})
```

Externalized bundles are smaller and may build faster, but the renderer needs the externalized packages available at runtime.

## Deployment

For a standard Rails + Vite deploy, there is nothing extra to configure. Keep running your normal asset build and the email bundle is emitted alongside your client assets.

### Standard Vite Builds

The plugin registers a dedicated `email` [build environment](https://vite.dev/guide/api-environment), so a normal `vite build` writes `tmp/react-email-rails/emails.js`, which the bundled production renderer runs with Node. With [rails_vite](https://github.com/skryukov/rails_vite/), this already happens during `assets:precompile`.

The bundle is required, not an optimization. If it's missing, renders raise `ReactEmailRails::RenderError` and no mail is sent. Make sure `vite build` runs anywhere that renders mail, the same as for the rest of your assets.

### Custom Vite Builds

To emit the bundle without a dedicated command, the plugin opts your project into Vite's [whole-app build](https://vite.dev/guide/api-environment):

- A plain `vite build` builds every configured environment in one pass. For a standard client-only app, that's just your client assets plus the `email` bundle.
- If you've defined other Vite environments, such as a custom `ssr` build, they build in the same pass too.
- If your Vite config defines a custom `builder.buildApp`, make sure it builds `builder.environments.email` alongside your other environments. Custom builders replace Vite's default whole-app build orchestration.

### Runtime Dependencies

For runtime dependency tradeoffs, see [Standalone Builds](#standalone-builds).

### Boot Verification

Boot verification is disabled by default. If you want the app to check the renderer during boot, scope it to the same processes that build or ship the bundle:

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
