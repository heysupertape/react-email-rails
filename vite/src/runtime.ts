import { render, type Options as ReactEmailRenderOptions } from "@react-email/render"
import React from "react"

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

export type HealthRequest = {
  health: true
}

export type RenderedEmail = {
  html: string
  text: string
}

export type EmailRenderOptions = {
  html?: ReactEmailRenderOptions
  text?: ReactEmailRenderOptions
}

export function toComponentName(globPath: string, root: string, extension: string): string {
  const start = globPath.lastIndexOf(root) + root.length
  return globPath.slice(start, globPath.length - extension.length)
}

export async function renderEmail(
  request: RenderRequest,
  registry: EmailRegistry,
): Promise<RenderedEmail> {
  const loader = registry[request.component]
  if (!loader) throw new Error(`React email component not found: ${request.component}`)

  const mod = typeof loader === "function" ? await loader() : loader
  const element = React.createElement(mod.default, request.props ?? {})

  // @react-email/render re-renders the tree per call, so html and text are two passes.
  return {
    html: await render(element, { ...request.renderOptions?.html, plainText: false }),
    text: await render(element, { ...request.renderOptions?.text, plainText: true }),
  }
}

export async function serve(registry: EmailRegistry): Promise<void> {
  if (process.argv.includes("--persistent")) {
    await servePersistent(registry, isolateStdout())
    return
  }

  if (process.argv.includes("--health")) {
    process.stdout.write(JSON.stringify({ ok: true }))
    return
  }

  const write = isolateStdout()
  try {
    const request = JSON.parse(await readStdin()) as RenderRequest
    write(JSON.stringify(await renderEmail(request, registry)))
  } catch (error) {
    process.stderr.write(error instanceof Error ? error.message : "React Email render failed")
    process.exitCode = 1
  }
}

// Reserve stdout for the JSON render protocol. Stray writes from email components
// or their dependencies — including console.log, which Node routes through
// process.stdout.write — are diverted to stderr so they cannot corrupt or desync
// a response frame. Returns the writer to use for protocol output.
function isolateStdout(): (chunk: string) => boolean {
  const protocolWrite = process.stdout.write.bind(process.stdout)
  process.stdout.write = ((chunk: string | Uint8Array): boolean =>
    process.stderr.write(chunk)) as typeof process.stdout.write
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
    if ("health" in request) {
      write(`${JSON.stringify({ ok: true })}\n`)
      return
    }

    write(`${JSON.stringify({ ok: true, ...(await renderEmail(request, registry)) })}\n`)
  } catch (error) {
    write(
      `${JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : "React Email render failed",
      })}\n`,
    )
  }
}
