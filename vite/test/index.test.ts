import React from "react"
import { describe, expect, it } from "vitest"

import { reactEmailRails } from "../src/index"
import { type EmailRegistry, renderEmail, serve, toComponentName } from "../src/runtime"

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
      "component not found",
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
    expect(responses[0]).toMatchObject({ ok: true })
    expect(responses[1].html).toContain("Hi Ada")
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
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('"/app/javascript/emails/**/*{.tsx,.jsx}"')
    expect(source).toContain('const extensions = [".tsx",".jsx"]')
    expect(source).toContain("export const run")
  })

  it("ignores underscore-prefixed partials by default", () => {
    const plugin = reactEmailRails()
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('"!/app/javascript/emails/**/_*"')
    expect(source).toContain('"!/app/javascript/emails/**/_*/**"')
  })

  it("accepts a custom ignore list and replaces the default", () => {
    const plugin = reactEmailRails({ emails: { ignore: ["shared/**", "components/**"] } })
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('"!/app/javascript/emails/shared/**"')
    expect(source).toContain('"!/app/javascript/emails/components/**"')
    expect(source).not.toContain("_*")
  })

  it("emits a plain string glob when ignore is disabled", () => {
    const plugin = reactEmailRails({ emails: { ignore: [] } })
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('import.meta.glob("/app/javascript/emails/**/*{.tsx,.jsx}")')
  })

  it("configures the build only for the email mode", () => {
    const plugin = reactEmailRails()
    const configHook = plugin.config as (
      config: object,
      env: { mode: string },
    ) => { build?: object } | undefined

    expect(configHook({}, { mode: "production" })).toBeUndefined()
    expect(configHook({}, { mode: "email" })?.build).toMatchObject({
      outDir: "tmp/react-email-rails",
    })
  })

  it("externalizes dependencies for the email build by default", () => {
    const plugin = reactEmailRails()
    const configHook = plugin.config as (
      config: object,
      env: { mode: string },
    ) => { ssr?: object } | undefined

    expect(configHook({}, { mode: "email" })?.ssr).toBeUndefined()
  })

  it("inlines dependencies for the email build when standalone is set", () => {
    const plugin = reactEmailRails({ standalone: true })
    const configHook = plugin.config as (
      config: object,
      env: { mode: string },
    ) => { ssr?: object } | undefined

    expect(configHook({}, { mode: "email" })?.ssr).toMatchObject({ noExternal: true })
  })

  it("accepts an emails string shorthand for the directory", () => {
    const plugin = reactEmailRails({ emails: "app/emails" })
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('"/app/emails/**/*{.tsx,.jsx}"')
  })

  it("keeps runtime render options out of the Vite virtual server", () => {
    const plugin = reactEmailRails()
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

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
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('"/app/javascript/emails/**/*{.tsx,.jsx}"')
    expect(source).toContain('const extensions = [".tsx",".jsx"]')
  })

  it("matches longer overlapping extensions before shorter suffixes", () => {
    const plugin = reactEmailRails({ emails: { extension: ["tsx", ".email.tsx"] } })
    const resolved = (plugin.resolveId as (id: string) => string | undefined)(
      "virtual:react-email-rails/server",
    )
    const source = (plugin.load as (id: string) => string | undefined)(resolved!)

    expect(source).toContain('"/app/javascript/emails/**/*{.email.tsx,.tsx}"')
    expect(source).toContain('const extensions = [".email.tsx",".tsx"]')
  })
})

function streamFromChunks(chunks: string[]): AsyncIterable<string> & { setEncoding: () => void } {
  return {
    setEncoding() {},
    async *[Symbol.asyncIterator]() {
      yield* chunks
    },
  }
}
