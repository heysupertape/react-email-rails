# Changelog

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
