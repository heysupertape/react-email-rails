#!/usr/bin/env node
import { createBuilder } from "vite"
import {
  exitIfHealthCheck,
  fail,
  isolatedViteConfig,
  loadReactEmailRailsConfig,
} from "./shared.mjs"

exitIfHealthCheck()

const args = process.argv.slice(2)
const readOption = (long, short) => {
  const prefixed = args.find((arg) => arg.startsWith(`${long}=`))
  if (prefixed) return prefixed.slice(long.length + 1)

  const longIndex = args.indexOf(long)
  if (longIndex !== -1) return args[longIndex + 1]

  if (!short) return undefined
  const shortIndex = args.indexOf(short)
  return shortIndex === -1 ? undefined : args[shortIndex + 1]
}

const root = args.find((arg, index) => {
  if (arg.startsWith("-")) return false
  const previous = args[index - 1]
  return (
    previous !== "--mode" &&
    previous !== "-m" &&
    previous !== "--config" &&
    previous !== "-c" &&
    previous !== "--configLoader" &&
    previous !== "--logLevel" &&
    previous !== "-l"
  )
})
const mode = readOption("--mode", "-m") ?? "production"
const configFile = readOption("--config", "-c")
const configLoader = readOption("--configLoader")
const logLevel = readOption("--logLevel", "-l")

process.env.NODE_ENV ??= "production"

const { userConfig, plugin, vite } = await loadReactEmailRailsConfig({
  command: "build",
  mode,
  root,
  configFile,
  logLevel,
  configLoader,
})

const builder = await createBuilder(
  isolatedViteConfig(userConfig, vite, {
    root: root ?? userConfig.root,
    configFile: false,
    mode,
    builder: {},
    plugins: [plugin],
    appType: "custom",
    clearScreen: false,
    logLevel,
  }),
  null,
)

const environment = builder.environments.email
if (!environment) fail("react-email-rails: email build environment not found")

await builder.build(environment)
