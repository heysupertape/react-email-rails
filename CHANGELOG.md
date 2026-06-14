# Changelog

## 0.6.1

- Fix `react:` rendering — and the `mailer`/`message` props — being skipped for actions that opt in through a class-level `default react: true` rather than a per-`mail` `react:` option. `mail` now resolves `react` (in any form: `true`, a component string, or a prop hash) from the mailer's `default`, a per-action `react: false` opts back out, and the internal `react`/`props`/`deep_merge` options never leak onto the message as email headers.

## 0.6.0

- Every `react:` email now receives `mailer` and `message` props, mirroring Action Mailer's `mailer`/`message` ERB view helpers. Rendering now happens after Action Mailer assigns headers, so `message` includes subject, addressing, and default `from`/`reply_to` values. Per-mail and shared props win on conflict, serializers whose `as_json` returns a Hash receive the context, and collection props keep their original shape. The npm package exports matching `Mailer`/`Message` TypeScript types.

## 0.5.0

- Add `react_email_share` for sharing props across every `react:` email a mailer renders, mirroring inertia-rails' `inertia_share`. Supports static values, lazy lambdas and blocks (evaluated in the mailer instance), `only`/`except`/`if`/`unless` filters, and subclass inheritance. Per-mail props win over shared props.
- Shared props merge shallowly by default. Pass `deep_merge: true` to `mail` to merge nested hashes, or set `config.deep_merge_shared_props = true` to make it the default.

## 0.4.1

- `ReactEmailRails.parse` now neutralizes unsafe link/button URI schemes: hrefs whose scheme is not `http`, `https`, `mailto`, or `tel` (e.g. `javascript:`/`data:`) are blanked before they reach the document `Hash`. Scheme detection ignores the whitespace and control characters browsers strip when resolving a scheme, so case- and whitespace-obfuscated payloads are caught too.

## 0.4.0

- `ReactEmailRails.parse` now accepts `markdown:` as an alternative to `html:`. Markdown is converted to HTML and runs through the same extension-driven parse path, producing the same document `Hash` — handy for agent- or tool-generated content. Pass exactly one of `html:`/`markdown:`.
- Add `marked` as an optional peer dependency, required only when calling `parse` with `markdown:`. HTML parsing and compose-only rendering do not require it.

## 0.3.0

- Add `ReactEmailRails.parse` to convert semantic HTML into a canonical `@react-email/editor` document using a renderer's extensions.
- Add `@tiptap/html` and `happy-dom` as optional peer dependencies, required only when calling `parse`; compose-only document rendering does not require them.
- Bump the render protocol to 3 (the renderer now accepts parse requests). The Ruby gem and npm package must be upgraded together, as before.

## 0.2.0

- Add `ReactEmailRails.compose` for server-side rendering of `@react-email/editor` documents to HTML and text.
- Add the `documents` Vite plugin option for discovering document renderers, parallel to `emails`.
- Report document nodes that render to nothing as non-fatal warnings on the result and instrumentation payload.
- Add `@react-email/editor` and `@tiptap/core` as optional peer dependencies (only required when rendering documents).
- Bump the render protocol to 2 (the renderer now accepts document requests). The Ruby gem and npm package must be upgraded together, as before.
- **Breaking:** `on_render_error` callbacks now receive `(error, **context)` with `kind:` plus `component:` for emails or `type:` for documents.

## 0.1.3

- Remove the `verify_render_on_boot` configuration option, which only logged on failure and duplicated the render-time `ReactEmailRails::RenderError`.
- Add the `react_email_rails:verify` rake task that checks the renderer and exits non-zero on failure.

## 0.1.2

- Support Vite 8 hook filters while keeping production email bundles standalone by default.
- Keep development email rendering compatible with Vite's module runner.

## 0.1.1

- Build production React Email bundles from Rails asset tasks with an isolated email-only Vite build.
- Add `react-email-rails-build` for direct production email bundle builds.

## 0.1.0

- Initial public release.
