#!/usr/bin/env node
import { createServer, isRunnableDevEnvironment, loadConfigFromFile } from "vite"
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
const loaded = await loadConfigFromFile({ command: "serve", mode: "development" })
const userConfig = loaded?.config ?? {}
const emailPlugin = (userConfig.plugins ?? [])
  .flat(Infinity)
  .find((plugin) => plugin?.name === "react-email-rails")

if (!emailPlugin) {
  process.stderr.write("react-email-rails: reactEmailRails() plugin not found in the Vite config\n")
  process.exit(1)
}

// Forward config that affects how components resolve and compile (but not the
// host's dev-server plugins, which have global side effects), so dev rendering
// stays close to the production email bundle.
const server = await createServer({
  configFile: false,
  resolve: userConfig.resolve,
  define: userConfig.define,
  css: userConfig.css,
  esbuild: { jsx: "automatic" },
  plugins: [emailPlugin],
  server: { middlewareMode: true },
  appType: "custom",
  clearScreen: false,
  customLogger: logger,
})

// Render through the same `email` environment the production build uses, so dev
// and build resolve and compile components identically.
const environment = server.environments.email
if (!isRunnableDevEnvironment(environment)) {
  await server.close()
  process.stderr.write("react-email-rails: the email environment is not runnable\n")
  process.exit(1)
}

try {
  const { run } = await environment.runner.import("virtual:react-email-rails/server")
  await run()
} finally {
  await server.close()
}
