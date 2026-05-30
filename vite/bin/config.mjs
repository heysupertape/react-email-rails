#!/usr/bin/env node
import { loadConfigFromFile } from "vite"

const loaded = await loadConfigFromFile({ command: "serve", mode: process.env.NODE_ENV ?? "development" })
const plugins = (loaded?.config?.plugins ?? []).flat(Infinity).filter(Boolean)
const plugin = plugins.find((plugin) => plugin.name === "react-email-rails")
const metadata = plugin?.[Symbol.for("react-email-rails.config")]

if (!plugin) {
  process.stderr.write("react-email-rails: reactEmailRails() plugin not found in the Vite config\n")
  process.exit(1)
}

if (!metadata) {
  process.stderr.write("react-email-rails: reactEmailRails() plugin metadata not found\n")
  process.exit(1)
}

process.stdout.write(JSON.stringify(metadata))
