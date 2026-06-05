![React Email + Rails](react-email-rails.png)

# React Email + Rails

Build and send emails using React and Rails — a seamless integration between [React Email](https://react.email) and [Action Mailer](https://guides.rubyonrails.org/action_mailer_basics.html).

## Contents

- [Why](#why)
- [How](#how)
- [Status](#status)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Editor](#editor)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Development](#development)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Why

Building HTML emails is painfully archaic. [React Email](https://react.email) is a collection of unstyled components for building emails with React, Tailwind, and TypeScript. This gem brings that power directly into your Rails app. Write emails as React components, send them through Action Mailer, and recipients get automatically generated HTML and text emails.

## How

**In development,** the gem renders components live through Vite's dev pipeline, so your emails get the same module resolution and transforms as the rest of your frontend.

**In production,** Rails builds a server-side email bundle during `assets:precompile`. The bundled rake task runs an isolated email-only Vite build, using `reactEmailRails()` in your app's Vite config for discovery and options.

React Email Rails automatically renders both HTML and plain-text versions from the same component. Delivery, headers, previews, queues, and callbacks all stay normal Action Mailer. If rendering fails, no email is sent and `ReactEmailRails::RenderError` is raised.

## Status

**react-email-rails is pre-1.0.** It's tested in CI across the supported Ruby, Rails, Node, and Vite versions, but it hasn't been battle-tested in high-volume production environments yet, and the API may still change before 1.0. Please [share feedback and report issues](https://github.com/heysupertape/react-email-rails/issues).

## Requirements

- Ruby >= 3.3
- Action Mailer, Active Support, and Railties >= 7.1 and < 9.0
- Node >= 20.19
- Vite 7 or 8
- React 18 or 19
- `@react-email/render` 2.x
- For [rendering editor documents](#editor) (optional): `@react-email/editor` 1.5+ and `@tiptap/core` 3.x

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

The installed setup follows the normal Rails lifecycle:

- `bin/rails generate react_email_rails:email ...` creates matching mailers and React components.
- Development renders through Vite on demand.
- `bin/rails assets:precompile` builds the production email bundle automatically.
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

The generator follows Rails' mailer generator shape: `NAME [method method]`. It creates `app/mailers/account_mailer.rb`, matching components under your configured React Email directory, plus a mailer preview and test.

The generator reads `emails.path` and `emails.extension` from `reactEmailRails()` when available. Pass flags to override them:

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

That's it — it now renders and delivers like any other Action Mailer email.

## Usage

Pass data from your mailers and each top-level key becomes a prop on the React component's default export.

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

  def welcome
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
| `AccountMailer#welcome` | `account_mailer/welcome` |
| `Users::InviteMailer#new_invite` | `users/invite_mailer/new_invite` |

Rails derives `account_mailer` from `AccountMailer` via its `mailer_name`. The default Vite plugin resolves those names under `app/javascript/emails`, so `account_mailer/welcome` maps to `app/javascript/emails/account_mailer/welcome.tsx` or `.jsx`.

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

## Editor

Alongside named components, the gem can render a [@react-email/editor](https://react.email/docs/editor) document — the Tiptap/ProseMirror JSON a visual editor produces — to HTML and text on the server.

React Email exposes [composeReactEmail](https://react.email/docs/editor/api-reference/compose-react-email) for this, but only from the browser, with a live editor instance from the export panel. `ReactEmailRails.compose` is the server analog: it rebuilds what `composeReactEmail` needs headlessly (no DOM, no live editor) from the stored document and the extensions you declare, then calls the same function. So `compose` is to the editor what `render` is to a component.

This is opt-in. The editor packages are optional peer dependencies and stay out of the email render path until you enable it.

### Setup

Install the editor packages:

```sh
npm i @react-email/editor @tiptap/core
```

To also parse HTML into documents with [`parse`](#parsing-html-into-a-document), add `@tiptap/html` and its server DOM, `happy-dom`:

```sh
npm i @tiptap/html happy-dom
```

Enable the `documents` option in your Vite config:

```ts
// vite.config.ts

import { defineConfig } from "vite"
import { reactEmailRails } from "react-email-rails"

export default defineConfig({
  plugins: [reactEmailRails({ documents: true })],
})
```

`documents: true` enables it with defaults (`app/javascript/documents`, `.ts`/`.tsx` extensions). Like `emails`, it also accepts a directory string or `{ path, extension, ignore }`. See [Plugin Options](#plugin-options).

### Document Renderers

A document doesn't carry the editor configuration it was authored with, so a headless renderer has to be told which extensions a given document needs. Each file under the documents directory is a **document renderer** — the editor-side analog of an email component — and its name is resolved from the directory layout just like [component names](#component-names) (so `broadcast` maps to `app/javascript/documents/broadcast.ts`).

```ts
// app/javascript/documents/broadcast.ts

import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"

// Required: the Tiptap extensions the document was authored with.
export function buildExtensions() {
  return [StarterKit, EmailTheming]
}
```

A renderer can export two optional hooks:

| Export | Required | Description |
|--------|----------|-------------|
| `buildExtensions(context)` | Yes | Returns the Tiptap extension list for the document. |
| `transformDocument(document, context)` | No | Returns a rewritten document before rendering — for example, to inject header/footer nodes that aren't persisted in the stored document. |
| `getPreview(context)` | No | Returns inbox preview text when the `compose` call doesn't pass one. |

`context` is the optional data you pass to `compose` (see below). Use it to vary extensions, transforms, or preview text per render.

```ts
// app/javascript/documents/broadcast.ts

import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"

export function buildExtensions(context) {
  return [StarterKit, EmailTheming]
}

// Inject a branded header after the persisted theme node, wherever it sits.
export function transformDocument(document, context) {
  const header = {
    type: "heading",
    attrs: { level: 1 },
    content: [{ type: "text", text: context.brandName }],
  }
  // Find globalContent and insert after it, rather than assuming a position, so
  // the theme node is preserved.
  const themeIndex = document.content.findIndex((node) => node.type === "globalContent")
  const at = themeIndex + 1
  return {
    ...document,
    content: [...document.content.slice(0, at), header, ...document.content.slice(at)],
  }
}

export function getPreview(context) {
  return context.previewText
}
```

> **Match the extensions to the document.** `composeReactEmail` renders any node whose extension isn't registered as `null`, so a document that uses a node your `buildExtensions` omits will silently drop that content. Return the same extension list the document was authored with.

> **Keep the theme node.** The editor persists its theme in a `globalContent` node and `EmailTheming` reads it back when rendering. If you reshape the document in `transformDocument`, preserve that node.

### Composing a Document

Call `ReactEmailRails.compose` with the renderer `type`, the stored document, and optional `context`/`preview`:

```ruby
broadcast = Broadcast.find(params[:id])

rendered = ReactEmailRails.compose(
  type: "broadcast",
  document: broadcast.body,          # a Hash in Tiptap's shape, e.g. from a jsonb column
  context: { brand_name: "Acme", preview_text: broadcast.subject },
  preview: broadcast.subject,        # optional; falls back to getPreview(context)
)

rendered.html # => "<!DOCTYPE html>..."
rendered.text # => "ACME\n\n..."
```

It returns the same `RenderedEmail` (`html`/`text`) as `render`, runs through the same [render modes](#render-modes), and raises `ReactEmailRails::RenderError` on failure. Documents don't go through Action Mailer — broadcasts and the like usually have their own delivery path — so deliver `rendered.html`/`rendered.text` however your app sends mail.

**The document is a `Hash`.** You pass and store it as a plain Ruby `Hash` with string keys — what a jsonb column hands back, and what [`parse`](#parsing-html-into-a-document) returns. "Tiptap JSON" names the document's *shape* (and the format it's serialized to over the wire to the renderer), not the Ruby type; `compose` accepts any object that responds to `as_json`, but a `Hash` is the norm.

**Keys:** the document's keys (`type`, `attrs`, `content`, `marks`, node names, `globalContent`) are structural and **passed through verbatim** — never transformed. Only `context` is key-transformed, camelized exactly like component props (so `brand_name` arrives as `brandName`, per [`transform_props`](#prop-transformation)).

`render_options` does not apply to documents; `composeReactEmail` controls its own rendering.

### Parsing HTML into a Document

`ReactEmailRails.parse` converts semantic HTML into the same document `Hash` shape the editor stores, using the selected renderer's extensions. This needs the `@tiptap/html` and `happy-dom` packages (see [Setup](#setup)).

```ruby
document = ReactEmailRails.parse(
  type: "broadcast",                 # the same renderer type compose uses
  html: params[:body_html],          # the HTML the caller sent
  context: { brand_name: "Acme" },   # optional; reaches buildExtensions, like compose
)

broadcast.update!(body: document)    # persist the Hash (e.g. to a jsonb column)
```

Later, render the stored document like any other:

```ruby
rendered = ReactEmailRails.compose(type: "broadcast", document: broadcast.body)
```

`parse` returns a plain Ruby `Hash` with string keys, normalized through the renderer's schema. It uses the same [render modes](#render-modes) as `compose` and raises `ReactEmailRails::RenderError` on failure. `context` is key-transformed like component props; the HTML is sent verbatim.

What this means in practice:

- HTML maps to a node only when an extension defines how to parse it. Unknown elements, inline styles, and classes may be dropped or flattened.
- Editor-only constructs such as custom email nodes and the persisted `globalContent` theme node do not round-trip from plain HTML.
- If you already have the document `Hash`, pass it to `compose` directly.

### Debugging Dropped Content

The most common integration bug is an extension/document mismatch. A node whose type is **missing from `buildExtensions` entirely** raises `ReactEmailRails::RenderError` (it can't be parsed) — loud and safe. The quiet case is a node that *is* in the schema but whose extension does not render to email (a plain Tiptap node rather than an email one): `composeReactEmail` renders it as nothing, with no error.

`compose` reports those dropped node types so the silent case isn't silent. They appear both on the result as `rendered.warnings` and on the [`render.react-email-rails`](#instrumentation) instrumentation event as `payload[:warnings]` — an array of `{ type:, count: }`. The editor's own non-rendering nodes (the `globalContent` theme node and similar) are excluded, so a non-empty `warnings` means real content was lost. Subscribe to the event to alert on it — or refuse to send:

```ruby
ActiveSupport::Notifications.subscribe("render.react-email-rails") do |event|
  warnings = event.payload[:warnings]
  raise "dropped #{warnings.sum { _1[:count] }} node(s): #{warnings.map { _1[:type] }.join(", ")}" if warnings
end
```

If content is missing, confirm `buildExtensions` returns the **same** extensions the document was authored with — the editor's `StarterKit` plus every custom node and plugin in use — and, if you reshape the document in `transformDocument`, that you preserved the `globalContent` theme node. Treat a mismatch as data or version skew: pinning a document's renderer `type` to the extension set it was created with, and versioning that set, avoids drift.

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
- The child is recycled after `render_process_max_requests` renders to bound memory growth. Set it to `nil` to disable recycling.

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

Use `on_render_error` to report failures before the exception is re-raised. The callback receives the error and a `context` of `kind:` (`"email"`, `"document"`, or `"parse"`) plus the identifier — `component:` for emails, `type:` for documents and parse requests. Accept `**context` so one handler covers every render kind:

```ruby
ReactEmailRails.configure do |config|
  config.on_render_error = ->(error, **context) {
    Rails.error.report(error, context:)
  }
end
```

#### Instrumentation

Every render emits an [ActiveSupport::Notifications](https://guides.rubyonrails.org/active_support_instrumentation.html) event named `render.react-email-rails`, so you can log render timing or forward it to your APM. The payload carries a `kind` (`"email"`, `"document"`, or `"parse"`), the `component` name (email) or `type` (document and parse), and, on a successful render, the rendered HTML size in `html_bytes` (omitted for `parse`, which returns a document rather than HTML). Document renders that drop content also include `warnings` (see [Debugging Dropped Content](#debugging-dropped-content)):

```ruby
ActiveSupport::Notifications.subscribe("render.react-email-rails") do |event|
  Rails.logger.info("[react-email-rails] Rendered #{event.payload[:component]} (Duration: #{event.duration.round}ms | Size: #{event.payload[:html_bytes]} bytes)")
end
```

### Vite Configuration

Most apps only need the `reactEmailRails()` plugin from [Quick Start](#quick-start). The options below change where components are discovered, how the bundle handles dependencies, and which email-only Vite transforms run in the isolated renderer.

In development and production, the isolated renderer loads the `reactEmailRails()` plugin, JSX support, and component-facing Vite config such as `resolve`, `define`, `css`, `json`, `assetsInclude`, `esbuild`, and `oxc` — but none of your other app plugins. Forwarded config is only for compiling and resolving email components; server, preview, dependency optimization, and build output settings stay owned by React Email Rails.

#### Plugin Options

| Option | Default | Description |
|--------|---------|-------------|
| `emails.path` | `"app/javascript/emails"` | Directory containing email components |
| `emails.extension` | `[".tsx", ".jsx"]` | Component extension, or an array of extensions |
| `emails.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `emails.path` |
| `documents` | `false` (off) | Enable [editor document rendering](#editor). `true`, a path string, or `{ path, extension, ignore }` |
| `documents.path` | `"app/javascript/documents"` | Directory containing document renderers |
| `documents.extension` | `[".ts", ".tsx"]` | Renderer extension, or an array of extensions |
| `documents.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `documents.path` |
| `standalone` | `true` | Inline production email bundle dependencies |
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

Most apps do not need extra email plugins. If email components need a transform that is not part of Vite's default pipeline, add that transform to the email renderer:

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

These `vite` options are used by `react-email-rails-dev` and `react-email-rails-build`. They are intentionally scoped to React Email. Only `assetsInclude`, `css`, `define`, `esbuild`, `json`, `oxc`, `plugins`, and `resolve` are accepted here; output settings such as `build.outDir` and `build.rollupOptions` are ignored so the Ruby renderer can always find the generated bundle.

#### Standalone Builds

By default the production email bundle inlines React, `@react-email/render`, and other Node dependencies. That makes the bundle larger, but it works well for Rails deploys that build assets in one stage and run without `node_modules` in the final runtime image. Development previews keep dependencies external for Vite's module runner, even when `standalone` is enabled.

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

The `react_email_rails:build` task is hooked into `assets:precompile` automatically. It loads your Vite config to find `reactEmailRails()` and its options, then writes `tmp/react-email-rails/emails.js` with the isolated React Email pipeline.

You can run it directly when needed:

```sh
bin/rails react_email_rails:build
```

Production rendering runs that bundle with Node. Set `SKIP_REACT_EMAIL_RAILS_BUILD=1` to skip the automatic asset hook. Directly running `bin/rails react_email_rails:build` always attempts the build.

The npm package, Vite, React, and `@react-email/render` must be available when Rails runs `assets:precompile`. This is the same stage where Rails apps normally install JavaScript dependencies and build frontend assets.

The bundle is required, not an optimization. If it's missing, renders raise `ReactEmailRails::RenderError` and no mail is sent.

The Ruby gem and npm package must stay on the same version. The renderer includes a small protocol/version handshake, so mismatched installs fail with an actionable `ReactEmailRails::RenderError` instead of silently returning malformed output.

The build command preserves `emails.path`, `emails.extension`, `emails.ignore`, `standalone`, and email-only `vite` options.

### Renderer Verification

To confirm the renderer is ready before relying on it, run:

```sh
bin/rails react_email_rails:verify
```

It checks that the render command runs and that the npm package version matches the gem, then exits non-zero with an actionable message on failure. Wire it into your CI or release step to catch a missing bundle or version drift before a deploy ships — a renderer failure won't otherwise surface until the first email is sent.

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
