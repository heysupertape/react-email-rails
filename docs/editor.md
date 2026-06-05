# Editor rendering

react-email-rails can render [@react-email/editor](https://react.email/docs/editor) documents to HTML and text on the server. It's for apps that store the Tiptap/ProseMirror JSON produced by a visual editor. Component-based Action Mailer emails don't need these packages.

React Email exposes [composeReactEmail](https://react.email/docs/editor/api-reference/compose-react-email) for browser use. `ReactEmailRails.compose` is the server analog. It rebuilds what `composeReactEmail` needs headlessly from the stored document and declared extensions, then calls the same function.

Editor rendering is opt-in. The editor packages are optional peer dependencies and stay out of the component email render path until you enable `documents`.

## Setup

Install the editor packages:

```sh
npm i @react-email/editor @tiptap/core
```

To also parse HTML into documents with [`parse`](#parsing-html-or-markdown-into-a-document), add `@tiptap/html` and its server DOM, `happy-dom`:

```sh
npm i @tiptap/html happy-dom
```

To parse Markdown as well, add [`marked`](https://marked.js.org). It converts Markdown to HTML, which then runs through the same parser:

```sh
npm i marked
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

`documents: true` uses the defaults (`app/javascript/documents`, `.ts`/`.tsx` extensions). Like `emails`, it also accepts a directory string or `{ path, extension, ignore }`.

## Configuration

The `documents` option controls where editor document renderers are discovered. It mirrors the `emails` option from the main README.

| Option | Default | Description |
|--------|---------|-------------|
| `documents` | `false` (off) | Enable editor document rendering. `true`, a path string, or `{ path, extension, ignore }` |
| `documents.path` | `"app/javascript/documents"` | Directory containing document renderers |
| `documents.extension` | `[".ts", ".tsx"]` | Renderer extension, or an array of extensions |
| `documents.ignore` | `["**/_*", "**/_*/**"]` | Glob patterns ignored under `documents.path` |

Use a custom directory:

```ts
reactEmailRails({
  documents: "app/documents",
})
```

Use multiple extensions:

```ts
reactEmailRails({
  documents: {
    extension: [".document.ts", ".document.tsx"],
  },
})
```

Document renderers share the same `standalone` and `vite` options as email components. If document renderers need a transform that isn't part of Vite's default pipeline, add it to the isolated renderer:

```ts
import mdx from "@mdx-js/rollup"
import { defineConfig } from "vite"
import { reactEmailRails } from "react-email-rails"

export default defineConfig({
  plugins: [
    reactEmailRails({
      documents: true,
      vite: {
        plugins: [mdx()],
      },
    }),
  ],
})
```

Standalone production bundles inline the editor dependencies needed by document renderers. This works well for Rails deploys that build assets in one stage and run without `node_modules` in the final image.

Editor renders use the same Rails render modes, error reporting, and instrumentation as component emails. For `on_render_error`, callbacks receive `kind:` (`"document"` or `"parse"`) and `type:` for the renderer name.

The `render.react-email-rails` instrumentation payload includes `kind`, `type`, successful HTML size in `html_bytes` for document renders, and `warnings` when content is dropped. `parse` returns a document rather than HTML, so it doesn't include `html_bytes`.

## Document renderers

A document doesn't carry the editor configuration it was authored with, so each file under the documents directory declares the extensions for one document type. Renderer names resolve from the directory layout just like [component names](../README.md#component-names), so `broadcast` maps to `app/javascript/documents/broadcast.ts`.

A document renderer exports `buildExtensions` and can also export optional hooks:

| Export | Required | Description |
|--------|----------|-------------|
| `buildExtensions(context)` | Yes | Returns the Tiptap extension list for the document. |
| `transformDocument(document, context)` | No | Rewrites the document before rendering, for example to inject header/footer nodes. |
| `getPreview(context)` | No | Returns inbox preview text when the `compose` call doesn't pass one. |

`context` is the optional data you pass to `compose`. Use it to vary extensions, transforms, or preview text per render.

```ts
// app/javascript/documents/broadcast.ts

import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"

export function buildExtensions(context) {
  return [StarterKit, EmailTheming]
}

export function transformDocument(document, context) {
  const header = {
    type: "heading",
    attrs: { level: 1 },
    content: [{ type: "text", text: context.brandName }],
  }
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

> **Match the extensions to the document.** `composeReactEmail` renders any unregistered node as `null`, so omitted extensions can silently drop content. Return the same extension list the document was authored with.

> **Keep the theme node.** The editor persists its theme in a `globalContent` node and `EmailTheming` reads it back when rendering. If you reshape the document in `transformDocument`, preserve that node.

## Composing a document

Call `ReactEmailRails.compose` with the renderer `type`, the stored document, and optional `context` or `preview`:

```ruby
broadcast = Broadcast.find(params[:id])

rendered = ReactEmailRails.compose(
  type: "broadcast",
  document: broadcast.body,
  context: { brand_name: "Acme", preview_text: broadcast.subject },
  preview: broadcast.subject,
)

rendered.html # => "<!DOCTYPE html>..."
rendered.text # => "ACME\n\n..."
```

It returns the same `RenderedEmail` (`html` and `text`) as `render`, uses the same [render modes](../README.md#render-modes), and raises `ReactEmailRails::RenderError` on failure. Documents don't go through Action Mailer, so deliver `rendered.html` and `rendered.text` through your app's mail path.

**The document is a `Hash`.** Store it as a plain Ruby `Hash` with string keys. This is what a jsonb column hands back, and what [`parse`](#parsing-html-or-markdown-into-a-document) returns. `compose` accepts any object that responds to `as_json`, but a `Hash` is the norm.

**Keys:** the document's keys (`type`, `attrs`, `content`, `marks`, node names, `globalContent`) are structural and passed through verbatim. Only `context` is key-transformed, camelized exactly like component props (so `brand_name` arrives as `brandName`, per [`transform_props`](../README.md#prop-transformation)).

`render_options` doesn't apply to documents. `composeReactEmail` controls its own rendering.

## Parsing HTML or Markdown into a document

`ReactEmailRails.parse` converts semantic HTML into the same document `Hash` shape the editor stores, using the selected renderer's extensions. This needs the `@tiptap/html` and `happy-dom` packages (see [Setup](#setup)).

```ruby
document = ReactEmailRails.parse(
  type: "broadcast",
  html: params[:body_html],
  context: { brand_name: "Acme" },
)

broadcast.update!(body: document)
```

Later, render the stored document like any other:

```ruby
rendered = ReactEmailRails.compose(type: "broadcast", document: broadcast.body)
```

`parse` returns a plain Ruby `Hash` with string keys, normalized through the renderer's schema. It uses the same [render modes](../README.md#render-modes) as `compose` and raises `ReactEmailRails::RenderError` on failure.

### Markdown

Pass `markdown:` instead of `html:` when a source emits Markdown more readily than HTML. It's converted to HTML with [`marked`](https://marked.js.org), so `marked` must be installed with the HTML peers (see [Setup](#setup)).

```ruby
document = ReactEmailRails.parse(
  type: "broadcast",
  markdown: "# Welcome\n\nThanks for signing up, **Ada**.",
  context: { brand_name: "Acme" },
)
```

Pass exactly one of `html:` or `markdown:`. Passing both, or neither, raises `ArgumentError`.

Markdown is a lower-friction *input*, not a wider one. It adds no new node types. Markdown that maps to unsupported nodes is dropped or flattened, like the equivalent HTML.

What this means in practice:

- HTML maps to a node only when an extension defines how to parse it. Unknown elements, inline styles, and classes may be dropped or flattened.
- Editor-only constructs such as custom email nodes and the persisted `globalContent` theme node don't round-trip from plain HTML or Markdown.
- If you already have the document `Hash`, pass it to `compose` directly.

## Debugging dropped content

The most common integration bug is an extension/document mismatch. A node type missing from `buildExtensions` raises `ReactEmailRails::RenderError`. The quieter case is a schema node whose extension doesn't render to email, which `composeReactEmail` renders as nothing.

`compose` reports dropped node types as `rendered.warnings` and as `payload[:warnings]` on the [`render.react-email-rails`](../README.md#instrumentation) event. Editor-owned non-rendering nodes are excluded, so non-empty warnings mean real content was lost:

```ruby
ActiveSupport::Notifications.subscribe("render.react-email-rails") do |event|
  warnings = event.payload[:warnings]
  raise "dropped #{warnings.sum { _1[:count] }} node(s): #{warnings.map { _1[:type] }.join(", ")}" if warnings
end
```

If content is missing, confirm `buildExtensions` returns the same extensions the document was authored with and that `transformDocument` preserves the `globalContent` theme node. Treat mismatches as data or version skew: pin a document's renderer `type` to its extension set, and version that set when it changes.
