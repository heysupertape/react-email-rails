# Changelog

## 0.2.0

- Add `ReactEmailRails.compose` for server-side rendering of `@react-email/editor` documents (Tiptap/ProseMirror JSON) to HTML and text, the server analog of the editor's client-side `composeReactEmail` export.
- Add the `documents` Vite plugin option for discovering document renderers, parallel to `emails`. It is off by default; the editor packages stay out of the email render path and build graph unless it is enabled.
- Add `@react-email/editor` and `@tiptap/core` as optional peer dependencies (only required when rendering documents).
- Bump the render protocol to 2 (the renderer now accepts document requests). The Ruby gem and npm package must be upgraded together, as before.
- **Breaking:** `on_render_error` callbacks now receive a uniform `(error, **context)` shape, where `context` carries `kind:` (`"email"`/`"document"`) and either `component:` (emails) or `type:` (documents). Update `->(error, component:) { ... }` callbacks to `->(error, **context) { ... }`.

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
