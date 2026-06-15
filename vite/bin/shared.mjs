import { loadConfigFromFile, mergeConfig } from "vite"

import { RENDER_PROTOCOL_VERSION, VERSION } from "../dist/version.js"

const CONFIG_SYMBOL = Symbol.for("react-email-rails.config")
const VITE_CONFIG_SYMBOL = Symbol.for("react-email-rails.vite")
const EMAIL_VITE_CONFIG_KEYS = [
  "assetsInclude",
  "css",
  "define",
  "esbuild",
  "json",
  "oxc",
  "plugins",
  "resolve",
]

export function exitIfHealthCheck() {
  if (!process.argv.includes("--health")) return

  process.stdout.write(
    JSON.stringify({
      ok: true,
      protocolVersion: RENDER_PROTOCOL_VERSION,
      packageVersion: VERSION,
    }),
  )
  process.exit(0)
}

export async function loadReactEmailRailsConfig({
  command,
  mode,
  root,
  configFile,
  logLevel,
  configLoader,
}) {
  const loaded = await loadConfigFromFile(
    { command, mode },
    configFile,
    root,
    logLevel,
    undefined,
    configLoader,
  )
  const userConfig = loaded?.config ?? {}
  const plugin = (userConfig.plugins ?? [])
    .flat(Infinity)
    .find((plugin) => plugin?.name === "react-email-rails")
  const metadata = plugin?.[CONFIG_SYMBOL]

  if (!plugin) fail("react-email-rails: reactEmailRails() plugin not found in the Vite config")
  if (!metadata) fail("react-email-rails: reactEmailRails() plugin metadata not found")

  return {
    userConfig,
    plugin,
    metadata,
    vite: plugin[VITE_CONFIG_SYMBOL] ?? {},
  }
}

export function isolatedViteConfig(userConfig, emailViteConfig, baseConfig) {
  const userEsbuild =
    userConfig.esbuild && typeof userConfig.esbuild === "object" ? userConfig.esbuild : {}
  const forwarded = {
    assetsInclude: userConfig.assetsInclude,
    resolve: userConfig.resolve,
    define: userConfig.define,
    css: userConfig.css,
    json: userConfig.json,
    oxc: userConfig.oxc,
    esbuild: { ...userEsbuild, jsx: userEsbuild.jsx ?? "automatic" },
  }

  return mergeConfig({ ...forwarded, ...baseConfig }, pickEmailViteConfig(emailViteConfig))
}

function pickEmailViteConfig(config) {
  return Object.fromEntries(
    EMAIL_VITE_CONFIG_KEYS.flatMap((key) =>
      config && Object.hasOwn(config, key) ? [[key, config[key]]] : [],
    ),
  )
}

export function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}
