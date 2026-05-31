#!/usr/bin/env node
import { loadReactEmailRailsConfig } from "./shared.mjs"

const { metadata } = await loadReactEmailRailsConfig({
  command: "serve",
  mode: process.env.NODE_ENV ?? "development",
})

process.stdout.write(JSON.stringify(metadata))
