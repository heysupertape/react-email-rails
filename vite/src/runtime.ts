import { render, type Options as ReactEmailRenderOptions } from "@react-email/render"
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

export type Mailer = {
  mailerName: string
  actionName: string
}

export type Message = {
  subject: string | null
  to: string[] | null
  cc: string[] | null
  bcc: string[] | null
  from: string[] | null
  replyTo: string[] | null
}

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
  if (!loader) throw new Error(`React email component not found: ${request.component}`)

  const mod = typeof loader === "function" ? await loader() : loader
  const element = React.createElement(mod.default, request.props ?? {})

  return {
    html: await render(element, {
      ...request.renderOptions?.html,
      plainText: false,
    }),
    text: await render(element, {
      ...request.renderOptions?.text,
      plainText: true,
    }),
  }
}

function isHealthRequest(request: unknown): request is HealthRequest {
  return request !== null && typeof request === "object" && "health" in request
}

export async function serve(registry: EmailRegistry): Promise<void> {
  if (process.argv.includes("--persistent")) {
    await servePersistent(registry, isolateStdout())
    return
  }

  if (process.argv.includes("--health")) {
    process.stdout.write(JSON.stringify(okResponse()))
    return
  }

  const write = isolateStdout()
  try {
    const request = JSON.parse(await readStdin()) as RenderRequest
    write(
      JSON.stringify({
        ...(await renderEmail(request, registry)),
        ...protocolMetadata(),
      }),
    )
  } catch (error) {
    process.stderr.write(error instanceof Error ? error.message : "React Email render failed")
    process.exitCode = 1
  }
}

function isolateStdout(): (chunk: string) => boolean {
  const protocolWrite = process.stdout.write.bind(process.stdout)
  process.stdout.write = ((chunk, encoding, callback) =>
    typeof encoding === "function"
      ? process.stderr.write(chunk, encoding)
      : process.stderr.write(chunk, encoding, callback)) as typeof process.stdout.write
  return (chunk) => protocolWrite(chunk)
}

function readStdin(): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = ""
    process.stdin.setEncoding("utf8")
    process.stdin.on("data", (chunk) => {
      data += chunk
    })
    process.stdin.on("end", () => resolve(data))
    process.stdin.on("error", reject)
  })
}

async function servePersistent(
  registry: EmailRegistry,
  write: (chunk: string) => boolean,
): Promise<void> {
  process.stdin.setEncoding("utf8")

  let pending = ""
  for await (const chunk of process.stdin) {
    pending += chunk

    let separator = pending.indexOf("\n")
    while (separator !== -1) {
      const line = pending.slice(0, separator)
      pending = pending.slice(separator + 1)

      if (line.trim()) await writePersistentResponse(line, registry, write)
      separator = pending.indexOf("\n")
    }
  }
}

async function writePersistentResponse(
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
