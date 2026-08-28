# Changelog

## 0.12.0

- **Breaking:** Remove `config.render_mode`. There is one renderer: a long-lived Node child per Ruby process, speaking newline-delimited JSON. Delete `config.render_mode = :persistent` from initializers. Set `config.render_process_max_requests = 1` to recycle the child after every email.
- **Breaking:** Replace `config.transform_props` (`:camel`, `:lower_camel`, `:dash`, `:snake`, `:none`) with `config.prop_transformer`, matching [inertia-rails](https://inertia-rails.dev/guide/configuration#prop_transformer). The default is a no-op (`->(props:) { props }`), so keys stay as `as_json` produced them. Camelize in an initializer if you want the previous 0.11 behavior. The exported `Mailer` and `Message` TypeScript types now describe that default snake_case shape.
- Render HTML once and derive plain text with `toPlainText`, so `htmlToTextOptions` and `data-skip-in-text` apply to the same markup.
- Raise clearer errors when a component is missing (including a capped list of known names) or has no default export.
- Default `render_timeout` to 30 seconds in development so the first Vite-backed render can finish booting.
- Timeouts with no stdout mention matching gem and npm versions, so a gem 0.12 talking to an older package that waits for EOF is easier to diagnose.
- Recycle the Node child after invalid JSON so the next render can succeed.
- Include Node stderr when the child exits without a protocol line, instead of reporting only that it exited.
- Treat only `{ "health": true }` as a health check so a render payload that also sets `health` still renders.
- Apply `html.pretty` only to the HTML body so pretty-printing does not change plain text.

## 0.11.1

- Republish of 0.11.0 with no code changes. The 0.11.0 npm package was never published: npm provenance publishing requires GitHub-hosted runners, so the release workflow's publish job now runs on one. Do not use gem 0.11.0; it has no matching npm package.

## 0.11.0

- Generated applications now use React Email 6's unified `react-email` package for email components instead of `@react-email/components`.
- `@react-email/render` is now a runtime dependency of the `react-email-rails` npm package instead of a peer dependency, so applications no longer install it directly. The npm package now declares `react-dom` as a peer dependency alongside `react`, matching what the renderer already required at runtime.

## 0.10.0

- **Breaking:** Remove the instance-level `react_share` helper (calling `react_share` from within an action before `mail`). Pass per-mail props directly in the `react:` hash instead; use the class-level `react_share` (with `only`/`except`/`if`/`unless`) for conditional sharing.

## 0.9.0

- **Breaking:** Rename `react_email_share` to `react_share`, matching the `react:` key used in `mail`. Update any `react_email_share` calls in your mailers to `react_share`.

## 0.8.0

- **Breaking:** Remove `@react-email/editor` document rendering to focus the library on component-based Action Mailer emails. `ReactEmailRails.compose`, `ReactEmailRails.parse`, the `documents` Vite plugin option, and the `react-email-rails/document` module are gone, along with the `@react-email/editor`, `@tiptap/core`, `@tiptap/html`, `happy-dom`, and `marked` optional peer dependencies.
- **Breaking:** `on_render_error` callbacks and the `render.react-email-rails` instrumentation payload no longer include `kind:` (every render is a component email again); `RenderedEmail` no longer has `warnings`.
- Bump the render protocol to 4 (the renderer no longer accepts document or parse requests). The Ruby gem and npm package must be upgraded together, as before.

## 0.7.0

- Add development live-reloading for Action Mailer previews. A development-only preview interceptor injects Vite's `@vite/client` into previews, and the `reactEmailRails()` plugin triggers a full reload when an email component changes, so the open preview refreshes on save. Configure the dev-server URL with `live_reload_url`, or set it to a falsy value to disable.

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
