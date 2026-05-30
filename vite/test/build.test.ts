import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
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

// Build a throwaway app through the plugin and return its root. The fixture is
// rooted under node_modules so React and @react-email/render resolve from the
// package's own dependencies, and so the scratch output stays gitignored.
async function buildFixture(options?: ReactEmailRailsOptions, extra?: Extra): Promise<string> {
  const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-build-"))
  fixtures.push(root)

  mkdirSync(join(root, "app/javascript/emails/account_mailer"), { recursive: true })
  writeFileSync(
    join(root, "index.html"),
    `<!doctype html><html><body><script type="module" src="/main.js"></script></body></html>`,
  )
  writeFileSync(join(root, "main.js"), "export const ok = true\n")
  // Plain createElement keeps the fixture free of JSX-transform config, so the
  // test stays focused on build orchestration rather than the host's JSX setup.
  writeFileSync(
    join(root, "app/javascript/emails/account_mailer/created.tsx"),
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

  const builder = await createBuilder(
    {
      root,
      configFile: false,
      logLevel: "silent",
      build: { outDir: "dist-client" },
      resolve: { alias: { "react-email-rails/runtime": runtimeEntry } },
      plugins: [reactEmailRails(options)],
      ...extra?.config,
    },
    // Passing null lets Vite derive whether to build the whole app from the
    // resolved `builder` option — so this exercises the plugin's opt-in rather
    // than forcing an app build from the test side.
    null,
  )
  await builder.buildApp()
  return root
}

describe("vite build", () => {
  it("emits the email bundle and the client output from a single plain build", async () => {
    const root = await buildFixture()

    // The email environment built without a separate `--mode email` step...
    expect(existsSync(join(root, "tmp/react-email-rails/emails.js"))).toBe(true)
    // ...with Node dependencies inlined by default...
    expect(readFileSync(join(root, "tmp/react-email-rails/emails.js"), "utf8")).not.toMatch(
      /from\s*"(react|@react-email\/render)"/,
    )
    // ...and the client environment still built in the same pass.
    expect(existsSync(join(root, "dist-client/index.html"))).toBe(true)
  }, 60_000)

  it("externalizes dependencies when standalone is false", async () => {
    const root = await buildFixture({ standalone: false })

    const bundle = readFileSync(join(root, "tmp/react-email-rails/emails.js"), "utf8")
    expect(bundle).toContain("@react-email/render")
  }, 60_000)

  it("builds the email bundle alongside a user-defined environment in one pass", async () => {
    // Opting into the whole-app build means any environment the host already
    // defines builds in the same pass — it must coexist with, not replace, them.
    const root = await buildFixture(undefined, {
      config: {
        environments: {
          ssr: {
            build: { ssr: true, outDir: "dist-ssr", rollupOptions: { input: "/ssr-entry.js" } },
          },
        },
      },
      files: { "ssr-entry.js": "export const ssr = true\n" },
    })

    expect(existsSync(join(root, "dist-client/index.html"))).toBe(true)
    expect(existsSync(join(root, "dist-ssr"))).toBe(true)
    expect(existsSync(join(root, "tmp/react-email-rails/emails.js"))).toBe(true)
  }, 60_000)
})
