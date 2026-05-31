#!/usr/bin/env node
import { createServer, isRunnableDevEnvironment } from "vite"
import { fail, isolatedViteConfig, loadReactEmailRailsConfig } from "./shared.mjs"
import { RENDER_PROTOCOL_VERSION, VERSION } from "../dist/version.js"

if (process.argv.includes("--health")) {
  process.stdout.write(JSON.stringify({ ok: true, protocolVersion: RENDER_PROTOCOL_VERSION, packageVersion: VERSION }))
  process.exit(0)
}

const toStderr = (message) => process.stderr.write(`${message}\n`)
const logger = {
  info: toStderr,
  warn: toStderr,
  warnOnce: toStderr,
  error: toStderr,
  clearScreen() {},
  hasErrorLogged: () => false,
  hasWarned: false,
}

// Load only this plugin and aliases; host dev-server plugins have global side effects.
const { userConfig, plugin, vite } = await loadReactEmailRailsConfig({
  command: "serve",
  mode: "development",
})

// Forward config that affects how components resolve and compile (but not the
// host's dev-server plugins, which have global side effects), so dev rendering
// stays close to the production email bundle.
const server = await createServer(
  isolatedViteConfig(userConfig, vite, {
    configFile: false,
    plugins: [plugin],
    server: { middlewareMode: true },
    appType: "custom",
    clearScreen: false,
    customLogger: logger,
  }),
)

// Render through the same `email` environment the production build uses, so dev
// and build resolve and compile components identically.
const environment = server.environments.email
if (!isRunnableDevEnvironment(environment)) {
  await server.close()
  fail("react-email-rails: the email environment is not runnable")
}

try {
  const { run } = await environment.runner.import("virtual:react-email-rails/server")
  await run()
} finally {
  await server.close()
}
