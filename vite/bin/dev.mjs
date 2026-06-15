#!/usr/bin/env node
import { createServer, isRunnableDevEnvironment } from "vite"
import {
  exitIfHealthCheck,
  fail,
  isolatedViteConfig,
  loadReactEmailRailsConfig,
} from "./shared.mjs"

exitIfHealthCheck()

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

const divertStdout = () => {
  const write = process.stdout.write.bind(process.stdout)
  process.stdout.write = (chunk, encoding, callback) => {
    if (typeof encoding === "function") return process.stderr.write(chunk, encoding)
    return process.stderr.write(chunk, encoding, callback)
  }
  return () => {
    process.stdout.write = write
  }
}

const restoreStdout = divertStdout()
const { userConfig, plugin, vite } = await loadReactEmailRailsConfig({
  command: "serve",
  mode: "development",
})

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

const environment = server.environments.email
if (!isRunnableDevEnvironment(environment)) {
  await server.close()
  fail("react-email-rails: the email environment is not runnable")
}

try {
  const { run } = await environment.runner.import("virtual:react-email-rails/server")
  restoreStdout()
  await run()
} finally {
  await server.close()
}
