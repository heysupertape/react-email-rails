import React from "react"
import { describe, expect, it } from "vitest"

import { RENDER_PROTOCOL_VERSION, VERSION, reactEmailRails } from "../src/index"
import { type EmailRegistry, renderEmail, serve, toComponentName } from "../src/runtime"

type EmailConfig = {
  builder?: object
  environments: {
    email: {
      resolve?: { noExternal?: boolean }
      build: {
        ssr?: boolean
        outDir?: string
        emptyOutDir?: boolean
        rollupOptions?: { input?: string; output?: { entryFileNames?: string } }
      }
    }
  }
}

const Welcome: React.ComponentType<Record<string, unknown>> = (props) =>
  React.createElement("p", null, `Hi ${String(props.name)}`)

describe("toComponentName", () => {
  it("strips the root directory and extension", () => {
    expect(
      toComponentName(
        "/app/javascript/emails/account_mailer/created.tsx",
        "/app/javascript/emails/",
        ".tsx",
      ),
    ).toBe("account_mailer/created")
  })
})

describe("renderEmail", () => {
  it("renders a lazy loader entry to html and text", async () => {
    const registry: EmailRegistry = { "account_mailer/created": async () => ({ default: Welcome }) }

    const result = await renderEmail(
      { component: "account_mailer/created", props: { name: "Ada" } },
      registry,
    )

    expect(result.html).toContain("Hi Ada")
    expect(result.text).toContain("Hi Ada")
  })

  it("renders an eager module entry", async () => {
    const registry: EmailRegistry = { "account_mailer/created": { default: Welcome } }

    const result = await renderEmail(
      { component: "account_mailer/created", props: { name: "Grace" } },
      registry,
    )

    expect(result.html).toContain("Hi Grace")
  })

  it("passes render options to React Email", async () => {
    const registry: EmailRegistry = { "account_mailer/created": { default: Welcome } }

    const result = await renderEmail(
      {
        component: "account_mailer/created",
        props: { name: "Ada" },
        renderOptions: { html: { pretty: true } },
      },
      registry,
    )

    expect(result.html).toContain("\n")
  })

  it("throws when the component is not found", async () => {
    await expect(renderEmail({ component: "nope/missing" }, {})).rejects.toThrow(
      "component not found: nope/missing",
    )
  })
})

describe("serve", () => {
  it("renders newline-delimited requests in persistent mode", async () => {
    const registry: EmailRegistry = { "account_mailer/created": { default: Welcome } }
    const originalArgv = process.argv
    const originalStdin = process.stdin
    const originalStdoutWrite = Reflect.get(process.stdout, "write") as typeof process.stdout.write
    const writes: string[] = []

    process.argv = [...process.argv, "--persistent"]
    Object.defineProperty(process, "stdin", {
      configurable: true,
      value: streamFromChunks([
        `${JSON.stringify({ health: true })}\n`,
        `${JSON.stringify({ component: "account_mailer/created", props: { name: "Ada" } })}\n`,
        `${JSON.stringify({ component: "account_mailer/created", props: { name: "Grace" } })}\n`,
      ]),
    })
    process.stdout.write = ((chunk: string | Uint8Array) => {
      writes.push(String(chunk))
      return true
    }) as typeof process.stdout.write

    try {
      await serve(registry)
    } finally {
      process.argv = originalArgv
      Object.defineProperty(process, "stdin", { configurable: true, value: originalStdin })
      process.stdout.write = originalStdoutWrite
    }

    const responses = writes
      .join("")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line))
    expect(responses).toHaveLength(3)
    expect(responses[0]).toMatchObject({
      ok: true,
      protocolVersion: RENDER_PROTOCOL_VERSION,
      packageVersion: VERSION,
    })
    expect(responses[1].html).toContain("Hi Ada")
    expect(responses[1]).toMatchObject({
      protocolVersion: RENDER_PROTOCOL_VERSION,
      packageVersion: VERSION,
    })
    expect(responses[2].html).toContain("Hi Grace")
  })
})

describe("serve stdout isolation", () => {
  it("keeps stray component stdout writes out of the render protocol", async () => {
    const Noisy: React.ComponentType<Record<string, unknown>> = (props) => {
      // Stand-in for a component (or dependency, or console.log) writing to stdout.
      process.stdout.write("noise-from-render\n")
      return React.createElement("p", null, `Hi ${String(props.name)}`)
    }
    const registry: EmailRegistry = { "x/noisy": { default: Noisy } }
    const originalArgv = process.argv
    const originalStdin = process.stdin
    const originalStdoutWrite = Reflect.get(process.stdout, "write") as typeof process.stdout.write
    const originalStderrWrite = Reflect.get(process.stderr, "write") as typeof process.stderr.write
    const stdout: string[] = []
    const stderr: string[] = []

    process.argv = [...process.argv, "--persistent"]
    Object.defineProperty(process, "stdin", {
      configurable: true,
      value: streamFromChunks([
        `${JSON.stringify({ component: "x/noisy", props: { name: "Ada" } })}\n`,
      ]),
    })
    process.stdout.write = ((chunk: string | Uint8Array) => {
      stdout.push(String(chunk))
      return true
    }) as typeof process.stdout.write
    process.stderr.write = ((chunk: string | Uint8Array) => {
      stderr.push(String(chunk))
      return true
    }) as typeof process.stderr.write

    try {
      await serve(registry)
    } finally {
      process.argv = originalArgv
      Object.defineProperty(process, "stdin", { configurable: true, value: originalStdin })
      process.stdout.write = originalStdoutWrite
      process.stderr.write = originalStderrWrite
    }

    const frames = stdout
      .join("")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line))
    expect(frames).toHaveLength(1)
    expect(frames[0]).toMatchObject({ ok: true })
    expect(frames[0].html).toContain("Hi Ada")
    expect(stderr.join("")).toContain("noise-from-render")
  })
})

describe("reactEmailRails plugin", () => {
  it("resolves and loads the server virtual module with the configured glob", () => {
    const plugin = reactEmailRails({ emails: { path: "app/javascript/emails" } })
    const source = loadVirtualServer(plugin)

    expect(source).toContain('"/app/javascript/emails/**/*{.tsx,.jsx}"')
    expect(source).toContain("buildRegistry(")
    expect(source).toContain('[".tsx",".jsx"], "/app/javascript/emails/")')
    expect(source).toContain("export const run")
  })

  it("filters virtual module hooks so host builds skip unrelated ids", () => {
    const plugin = reactEmailRails()
    const resolveId = plugin.resolveId as FilteredHook<(id: string) => string | undefined, RegExp>
    const load = plugin.load as FilteredHook<(id: string) => string | undefined, RegExp>

    expect(resolveId.filter.id.test("virtual:react-email-rails/server")).toBe(true)
    expect(resolveId.filter.id.test("react")).toBe(false)
    expect(load.filter.id.test("\0virtual:react-email-rails/server")).toBe(true)
    expect(load.filter.id.test("/app/frontend/main.tsx")).toBe(false)
  })

  it("keeps normalized plugin metadata for Rails generators behind an internal symbol", () => {
    const plugin = reactEmailRails({
      emails: { path: "/app/frontend/emails/", extension: "jsx" },
      standalone: true,
    })
    const metadata = (plugin as unknown as Record<symbol, unknown>)[
      Symbol.for("react-email-rails.config")
    ]

    expect(metadata).toMatchObject({
      emails: {
        path: "app/frontend/emails",
        extensions: [".jsx"],
      },
      standalone: true,
    })
  })

  it("keeps isolated Vite options behind an internal symbol", () => {
    const emailPlugin = { name: "email-only" }
    const plugin = reactEmailRails({
      vite: { define: { __EMAIL__: JSON.stringify(true) }, plugins: [emailPlugin] },
    })
    const viteOptions = (plugin as unknown as Record<symbol, unknown>)[
      Symbol.for("react-email-rails.vite")
    ]

    expect(viteOptions).toMatchObject({
      define: { __EMAIL__: "true" },
      plugins: [emailPlugin],
    })
  })

  it("ignores underscore-prefixed partials by default", () => {
    const plugin = reactEmailRails()
    const source = loadVirtualServer(plugin)

    expect(source).toContain('"!/app/javascript/emails/**/_*"')
    expect(source).toContain('"!/app/javascript/emails/**/_*/**"')
  })

  it("accepts a custom ignore list and replaces the default", () => {
    const plugin = reactEmailRails({ emails: { ignore: ["shared/**", "components/**"] } })
    const source = loadVirtualServer(plugin)

    expect(source).toContain('"!/app/javascript/emails/shared/**"')
    expect(source).toContain('"!/app/javascript/emails/components/**"')
    expect(source).not.toContain("_*")
  })

  it("emits a plain string glob when ignore is disabled", () => {
    const plugin = reactEmailRails({ emails: { ignore: [] } })
    const source = loadVirtualServer(plugin)

    expect(source).toContain('import.meta.glob("/app/javascript/emails/**/*{.tsx,.jsx}")')
  })

  it("registers the email build environment for the dedicated renderer", () => {
    const plugin = reactEmailRails()
    const config = pluginConfig(plugin, "build")

    expect(config.builder).toBeUndefined()
    expect(config.environments.email.build).toMatchObject({
      ssr: true,
      outDir: "tmp/react-email-rails",
      emptyOutDir: true,
    })
    expect(config.environments.email.build.rollupOptions).toMatchObject({
      input: "virtual:react-email-rails/main",
      output: { entryFileNames: "emails.js" },
    })
  })

  it("inlines dependencies for the email build by default", () => {
    const plugin = reactEmailRails()
    const config = pluginConfig(plugin, "build")

    expect(config.environments.email.resolve).toMatchObject({ noExternal: true })
  })

  it("keeps dev module-runner dependencies external even when standalone is true", () => {
    const plugin = reactEmailRails()
    const config = pluginConfig(plugin, "serve")

    expect(config.environments.email.resolve).toBeUndefined()
  })

  it("externalizes dependencies for the email build when standalone is false", () => {
    const plugin = reactEmailRails({ standalone: false })
    const config = pluginConfig(plugin, "build")

    expect(config.environments.email.resolve).toBeUndefined()
  })

  it("accepts an emails string shorthand for the directory", () => {
    const plugin = reactEmailRails({ emails: "app/emails" })
    const source = loadVirtualServer(plugin)

    expect(source).toContain('"/app/emails/**/*{.tsx,.jsx}"')
  })

  it("keeps runtime render options out of the Vite virtual server", () => {
    const plugin = reactEmailRails()
    const source = loadVirtualServer(plugin)

    expect(source).toContain("serve(registry)")
    expect(source).not.toContain("renderOptions")
  })

  it("normalizes extension options and strips the full configured extension", () => {
    expect(
      toComponentName(
        "/app/javascript/emails/account_mailer/created.email.tsx",
        "/app/javascript/emails/",
        ".email.tsx",
      ),
    ).toBe("account_mailer/created")

    const plugin = reactEmailRails({ emails: { extension: ["tsx", ".jsx"] } })
    const source = loadVirtualServer(plugin)

    expect(source).toContain('"/app/javascript/emails/**/*{.tsx,.jsx}"')
    expect(source).toContain("buildRegistry(")
    expect(source).toContain('[".tsx",".jsx"], "/app/javascript/emails/")')
  })

  it("matches longer overlapping extensions before shorter suffixes", () => {
    const plugin = reactEmailRails({ emails: { extension: ["tsx", ".email.tsx"] } })
    const source = loadVirtualServer(plugin)

    expect(source).toContain('"/app/javascript/emails/**/*{.email.tsx,.tsx}"')
    expect(source).toContain('[".email.tsx",".tsx"], "/app/javascript/emails/")')
  })
})

describe("reactEmailRails preview live reload", () => {
  it("broadcasts a full reload when a file under the email path changes", () => {
    const plugin = reactEmailRails()
    const { sent, result } = handleHotUpdate(
      plugin,
      "/project/app/javascript/emails/account_mailer/welcome.tsx",
    )

    expect(sent).toEqual([{ type: "full-reload" }])
    expect(result).toEqual([])
  })

  it("broadcasts for newly created files under the email path", () => {
    const plugin = reactEmailRails()
    const { sent, result } = handleHotUpdate(
      plugin,
      "/project/app/javascript/emails/account_mailer/reset.tsx",
      "/project",
      "create",
    )

    expect(sent).toEqual([{ type: "full-reload" }])
    expect(result).toEqual([])
  })

  it("leaves non-client environments to invalidate normally", () => {
    const plugin = reactEmailRails()
    const { sent, result } = handleHotUpdate(
      plugin,
      "/project/app/javascript/emails/account_mailer/welcome.tsx",
      "/project",
      "update",
      "email",
    )

    expect(sent).toEqual([])
    expect(result).toBeUndefined()
  })

  it("reloads for any file under the email path, including ignored partials and styles", () => {
    const plugin = reactEmailRails()

    expect(
      handleHotUpdate(plugin, "/project/app/javascript/emails/_components/layout.tsx").sent,
    ).toEqual([{ type: "full-reload" }])
    expect(handleHotUpdate(plugin, "/project/app/javascript/emails/styles.css").sent).toEqual([
      { type: "full-reload" },
    ])
  })

  it("ignores changes outside the email path", () => {
    const plugin = reactEmailRails()
    const { sent, result } = handleHotUpdate(plugin, "/project/app/javascript/controllers/hello.ts")

    expect(sent).toEqual([])
    expect(result).toBeUndefined()
  })

  it("does not reload for a sibling directory that shares the email path prefix", () => {
    const plugin = reactEmailRails()

    expect(handleHotUpdate(plugin, "/project/app/javascript/emails-archive/old.tsx").sent).toEqual(
      [],
    )
  })

  it("reloads for the configured custom email path", () => {
    const plugin = reactEmailRails({ emails: "app/emails" })

    expect(handleHotUpdate(plugin, "/project/app/emails/welcome.tsx").sent).toEqual([
      { type: "full-reload" },
    ])
    expect(handleHotUpdate(plugin, "/project/app/javascript/emails/welcome.tsx").sent).toEqual([])
  })
})

type FilteredHook<T, I = RegExp> = {
  filter: { id: I }
  handler: T
}

function loadVirtualServer(plugin: ReturnType<typeof reactEmailRails>): string {
  const resolved = resolveId(plugin, "virtual:react-email-rails/server")

  return load(plugin, resolved!)
}

function resolveId(plugin: ReturnType<typeof reactEmailRails>, id: string): string | undefined {
  const hook = plugin.resolveId as FilteredHook<(id: string) => string | undefined>

  return hook.handler(id)
}

function load(plugin: ReturnType<typeof reactEmailRails>, id: string): string {
  const hook = plugin.load as FilteredHook<(id: string) => string | undefined>
  const source = hook.handler(id)

  if (!source) throw new Error(`expected source for ${id}`)
  return source
}

function handleHotUpdate(
  plugin: ReturnType<typeof reactEmailRails>,
  file: string,
  root = "/project",
  type: "create" | "update" | "delete" = "update",
  environmentName = "client",
): { sent: unknown[]; result: unknown } {
  const sent: unknown[] = []
  const environment = {
    name: environmentName,
    hot: { send: (payload: unknown) => sent.push(payload) },
  }
  const options = {
    type,
    file,
    timestamp: 0,
    modules: [],
    read: () => "",
    server: { config: { root } },
  }
  const hook = plugin.hotUpdate as unknown as (
    this: { environment: typeof environment },
    context: typeof options,
  ) => unknown

  return { sent, result: hook.call({ environment }, options) }
}

function pluginConfig(plugin: ReturnType<typeof reactEmailRails>, command: "build" | "serve") {
  const hook = plugin.config as unknown as (
    config: Record<string, never>,
    env: { command: "build" | "serve"; mode: string; isSsrBuild?: boolean; isPreview?: boolean },
  ) => EmailConfig

  return hook({}, { command, mode: command === "build" ? "production" : "development" })
}

function streamFromChunks(chunks: string[]): AsyncIterable<string> & { setEncoding: () => void } {
  return {
    setEncoding() {},
    async *[Symbol.asyncIterator]() {
      yield* chunks
    },
  }
}
