import {
  pretty as prettyHtml,
  render,
  toPlainText,
  unstableToPlainText,
  type Options as ReactEmailRenderOptions,
} from "@react-email/render"
import React from "react"

import { RENDER_PROTOCOL_VERSION, VERSION } from "./version.js"

export type EmailModule = {
  default: React.ComponentType<Record<string, unknown>>
}

export type EmailLoader = EmailModule | (() => Promise<EmailModule>)
export type EmailRegistry = Record<string, EmailLoader>

export type RenderRequest = {
  component: string
  props?: Record<string, unknown>
  renderOptions?: EmailRenderOptions
}

export type {
  CamelMailer,
  CamelMessage,
  SnakeMailer as Mailer,
  SnakeMessage as Message,
} from "./types.js"

export type HealthRequest = {
  health: true
}

export type RenderedEmail = {
  html: string
  text: string
}

type ProtocolMetadata = {
  protocolVersion: number
  packageVersion: string
}

export type EmailRenderOptions = {
  html?: ReactEmailRenderOptions
  text?: ReactEmailRenderOptions
}

export function toComponentName(globPath: string, root: string, extension: string): string {
  const start = globPath.lastIndexOf(root) + root.length
  return globPath.slice(start, globPath.length - extension.length)
}

export function buildRegistry(
  modules: EmailRegistry,
  extensions: string[],
  root: string,
): EmailRegistry {
  const registry: EmailRegistry = Object.create(null)
  for (const [path, loader] of Object.entries(modules)) {
    const extension =
      extensions.find((ext) => path.endsWith(ext)) ?? path.slice(path.lastIndexOf("."))
    registry[toComponentName(path, root, extension)] = loader
  }
  return registry
}

export async function renderEmail(
  request: RenderRequest,
  registry: EmailRegistry,
): Promise<RenderedEmail> {
  const loader = registry[request.component]
  if (!loader) {
    throw new Error(
      `React email component not found: ${request.component}.${missingComponentHint(registry)}`,
    )
  }

  const mod = typeof loader === "function" ? await loader() : loader
  if (mod?.default == null) {
    throw new Error(`React email component ${request.component} must have a default export`)
  }

  const element = React.createElement(mod.default, request.props ?? {})
  const htmlOptions = request.renderOptions?.html
  const html = await render(element, {
    ...htmlOptions,
    plainText: false,
    pretty: false,
  })
  const textOptions = request.renderOptions?.text

  return {
    html: htmlOptions?.pretty ? await prettyHtml(html) : html,
    text: plainTextFromHtml(html, textOptions),
  }
}

const MISSING_COMPONENT_LIST_LIMIT = 12

function missingComponentHint(registry: EmailRegistry): string {
  const available = Object.keys(registry).sort()
  if (available.length === 0) return ""

  const shown = available.slice(0, MISSING_COMPONENT_LIST_LIMIT)
  const rest = available.length - shown.length
  const list = rest > 0 ? `${shown.join(", ")}, and ${rest} more` : shown.join(", ")
  return ` Available components: ${list}`
}

function plainTextFromHtml(html: string, textOptions: EmailRenderOptions["text"]): string {
  if (
    textOptions &&
    "unstableTextConversion" in textOptions &&
    textOptions.unstableTextConversion
  ) {
    return unstableToPlainText(html)
  }

  const htmlToTextOptions =
    textOptions && "htmlToTextOptions" in textOptions ? textOptions.htmlToTextOptions : undefined
  return toPlainText(html, htmlToTextOptions)
}

function isHealthRequest(request: unknown): request is HealthRequest {
  if (request === null || typeof request !== "object") return false
  const value = request as Record<string, unknown>
  return value.health === true && !("component" in value)
}

export async function serve(registry: EmailRegistry): Promise<void> {
  if (process.argv.includes("--health")) {
    process.stdout.write(JSON.stringify(okResponse()))
    return
  }

  const write = isolateStdout()
  process.stdin.setEncoding("utf8")

  let pending = ""
  for await (const chunk of process.stdin) {
    pending += chunk

    let separator = pending.indexOf("\n")
    while (separator !== -1) {
      const line = pending.slice(0, separator)
      pending = pending.slice(separator + 1)

      if (line.trim()) await writeResponse(line, registry, write)
      separator = pending.indexOf("\n")
    }
  }

  if (pending.trim()) await writeResponse(pending, registry, write)
}

function isolateStdout(): (chunk: string) => boolean {
  const protocolWrite = process.stdout.write.bind(process.stdout)
  process.stdout.write = ((chunk, encoding, callback) =>
    typeof encoding === "function"
      ? process.stderr.write(chunk, encoding)
      : process.stderr.write(chunk, encoding, callback)) as typeof process.stdout.write
  return (chunk) => protocolWrite(chunk)
}

async function writeResponse(
  line: string,
  registry: EmailRegistry,
  write: (chunk: string) => boolean,
): Promise<void> {
  try {
    const request = JSON.parse(line) as RenderRequest | HealthRequest
    if (isHealthRequest(request)) {
      write(`${JSON.stringify(okResponse())}\n`)
      return
    }

    write(
      `${JSON.stringify({ ok: true, ...(await renderEmail(request, registry)), ...protocolMetadata() })}\n`,
    )
  } catch (error) {
    write(
      `${JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : "React Email render failed",
      })}\n`,
    )
  }
}

function okResponse(): { ok: true } & ProtocolMetadata {
  return { ok: true, ...protocolMetadata() }
}

function protocolMetadata(): ProtocolMetadata {
  return {
    protocolVersion: RENDER_PROTOCOL_VERSION,
    packageVersion: VERSION,
  }
}
