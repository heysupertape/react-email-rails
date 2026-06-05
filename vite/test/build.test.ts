import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

import { createBuilder, type InlineConfig } from "vite"
import { afterAll, describe, expect, it } from "vitest"

import { reactEmailRails, type ReactEmailRailsOptions } from "../src/index"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")
const runtimeEntry = join(pkgRoot, "src/runtime.ts")
const fixtures: string[] = []

afterAll(() => {
  for (const dir of fixtures) rmSync(dir, { recursive: true, force: true })
})

type Extra = { config?: InlineConfig; files?: Record<string, string> }
type BuildResult = { root: string; resolveCalls: number; loadCalls: number }

// Build a throwaway app through the plugin and return its root. Rooted under node_modules so
// React/@react-email/render resolve from the package's deps and the scratch output stays gitignored.
async function buildFixture(options?: ReactEmailRailsOptions, extra?: Extra): Promise<BuildResult> {
  const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-build-"))
  fixtures.push(root)

  mkdirSync(join(root, "app/javascript/emails/account_mailer"), { recursive: true })
  writeFileSync(
    join(root, "index.html"),
    `<!doctype html><html><body><script type="module" src="/main.js"></script></body></html>`,
  )
  writeFileSync(join(root, "main.js"), "export const ok = true\n")
  // Plain createElement avoids JSX-transform config, keeping the test on build orchestration.
  writeFileSync(
    join(root, "app/javascript/emails/account_mailer/created.tsx"),
    'import "email-only-missing-module"\n' +
      'import { createElement } from "react"\n\n' +
      "export default function Created({ account }: { account: { name: string } }) {\n" +
      '  return createElement("p", null, `Welcome to ${account.name}`)\n' +
      "}\n",
  )
  writeFileSync(
    join(root, "app/javascript/emails/account_mailer/partial.tsx"),
    'import { createElement } from "react"\n\n' +
      "export default function Created({ account }: { account: { name: string } }) {\n" +
      '  return createElement("p", null, `Welcome to ${account.name}`)\n' +
      "}\n",
  )
  for (const [relativePath, content] of Object.entries(extra?.files ?? {})) {
    const absolutePath = join(root, relativePath)
    mkdirSync(dirname(absolutePath), { recursive: true })
    writeFileSync(absolutePath, content)
  }

  const plugin = reactEmailRails(options)
  let resolveCalls = 0
  let loadCalls = 0
  wrapHook(plugin, "resolveId", () => resolveCalls++)
  wrapHook(plugin, "load", () => loadCalls++)

  const builder = await createBuilder(
    {
      root,
      configFile: false,
      logLevel: "silent",
      build: { outDir: "dist-client" },
      resolve: { alias: { "react-email-rails/runtime": runtimeEntry } },
      plugins: [plugin],
      ...extra?.config,
    },
    null,
  )
  await builder.buildApp()
  return { root, resolveCalls, loadCalls }
}

describe("vite build", () => {
  it("builds client assets without building production emails", async () => {
    const { root, resolveCalls, loadCalls } = await buildFixture()

    expect(existsSync(join(root, "dist-client/index.html"))).toBe(true)
    expect(existsSync(join(root, "tmp/react-email-rails/emails.js"))).toBe(false)
    expect(resolveCalls).toBe(0)
    expect(loadCalls).toBe(0)
  }, 60_000)
})

function wrapHook(
  plugin: ReturnType<typeof reactEmailRails>,
  name: "resolveId" | "load",
  onCall: () => void,
): void {
  const hook = plugin[name] as
    | ((...args: unknown[]) => unknown)
    | { handler: (...args: unknown[]) => unknown }
    | undefined

  if (!hook) return

  if (typeof hook === "function") {
    plugin[name] = function (this: unknown, ...args: unknown[]) {
      onCall()
      return hook.apply(this, args)
    } as never
    return
  }

  const handler = hook.handler
  plugin[name] = {
    ...hook,
    handler(this: unknown, ...args: unknown[]) {
      onCall()
      return handler.apply(this, args)
    },
  } as never
}
