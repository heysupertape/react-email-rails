# Changelog

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
