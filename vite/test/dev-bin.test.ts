import { spawn } from "node:child_process"
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

import { afterAll, describe, expect, it } from "vitest"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")
const runtimeEntry = join(pkgRoot, "src/runtime.ts")
const fixtures: string[] = []

afterAll(() => {
  for (const dir of fixtures) rmSync(dir, { recursive: true, force: true })
})

describe("react-email-rails-dev", () => {
  it("renders through Vite's module runner without disabling standalone in user config", async () => {
    const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-dev-bin-"))
    fixtures.push(root)

    mkdirSync(join(root, "app/frontend/emails/account_mailer"), { recursive: true })
    mkdirSync(join(root, "node_modules/cjs-helper"), { recursive: true })
    writeFileSync(
      join(root, "node_modules/cjs-helper/package.json"),
      JSON.stringify({ name: "cjs-helper", version: "1.0.0", main: "index.cjs" }),
    )
    writeFileSync(
      join(root, "node_modules/cjs-helper/index.cjs"),
      [
        `const label = "from-cjs"`,
        `module.exports = function decorate(value) {`,
        `  return label + ":" + value`,
        `}`,
        ``,
      ].join("\n"),
    )
    writeFileSync(
      join(root, "vite.config.ts"),
      [
        `import { defineConfig } from "vite"`,
        `import { reactEmailRails } from ${JSON.stringify(
          pathToFileURL(join(pkgRoot, "dist/index.js")).href,
        )}`,
        ``,
        `export default defineConfig({`,
        `  resolve: {`,
        `    alias: { "react-email-rails/runtime": ${JSON.stringify(runtimeEntry)} },`,
        `  },`,
        `  plugins: [reactEmailRails({ emails: "app/frontend/emails" })],`,
        `})`,
        ``,
      ].join("\n"),
    )
    writeFileSync(
      join(root, "app/frontend/emails/account_mailer/created.tsx"),
      [
        `import { createElement } from "react"`,
        `import decorate from "cjs-helper"`,
        ``,
        `export default function Created({ name }: { name: string }) {`,
        `  return createElement("p", null, decorate(name))`,
        `}`,
        ``,
      ].join("\n"),
    )

    const result = await runDevRenderer(root, {
      component: "account_mailer/created",
      props: { name: "Ada" },
    })

    expect(result.html).toContain("from-cjs:Ada")
    expect(result.text).toContain("from-cjs:Ada")
  }, 60_000)
})

function runDevRenderer(root: string, request: unknown): Promise<{ html: string; text: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn("node", [join(pkgRoot, "bin/dev.mjs")], {
      cwd: root,
      stdio: ["pipe", "pipe", "pipe"],
    })
    let stdout = ""
    let stderr = ""

    child.stdout.setEncoding("utf8")
    child.stderr.setEncoding("utf8")
    child.stdout.on("data", (chunk) => {
      stdout += chunk
    })
    child.stderr.on("data", (chunk) => {
      stderr += chunk
    })
    child.on("error", reject)
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(`react-email-rails-dev exited ${code}\n${stderr}\n${stdout}`))
        return
      }

      try {
        resolve(JSON.parse(stdout))
      } catch (error) {
        reject(
          new Error(`react-email-rails-dev returned invalid JSON\n${stderr}\n${stdout}`, {
            cause: error,
          }),
        )
      }
    })

    child.stdin.end(JSON.stringify(request))
  })
}
