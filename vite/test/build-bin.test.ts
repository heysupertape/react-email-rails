import { execFile as execFileCallback } from "node:child_process"
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { promisify } from "node:util"

import { afterAll, describe, expect, it } from "vitest"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")
const runtimeEntry = join(pkgRoot, "src/runtime.ts")
const fixtures: string[] = []
const execFile = promisify(execFileCallback)

afterAll(() => {
  for (const dir of fixtures) rmSync(dir, { recursive: true, force: true })
})

describe("react-email-rails-build", () => {
  it("builds only the isolated email environment from a host Vite config", async () => {
    const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-build-bin-"))
    fixtures.push(root)

    mkdirSync(join(root, "app/frontend/emails/account_mailer"), { recursive: true })
    mkdirSync(join(root, "app/frontend/emails/ignored"), { recursive: true })
    writeFileSync(
      join(root, "vite.config.ts"),
      [
        `import { defineConfig } from "vite"`,
        `import { reactEmailRails } from ${JSON.stringify(
          pathToFileURL(join(pkgRoot, "dist/index.js")).href,
        )}`,
        ``,
        `function unrelatedHostPlugin() {`,
        `  return {`,
        `    name: "unrelated-host-plugin",`,
        `    configResolved() { throw new Error("unrelated host plugin configResolved ran") },`,
        `    buildStart() { throw new Error("unrelated host plugin buildStart ran") },`,
        `  }`,
        `}`,
        `function emailOnlyPlugin() {`,
        `  return {`,
        `    name: "email-only-plugin",`,
        `    resolveId(id) { if (id === "virtual:email-marker") return id },`,
        `    load(id) { if (id === "virtual:email-marker") return "export const marker = 'email-only-plugin-ran'" },`,
        `  }`,
        `}`,
        ``,
        `export default defineConfig({`,
        `  resolve: {`,
        `    alias: {`,
        `      "@emails": ${JSON.stringify(join(root, "app/frontend/emails"))},`,
        `      "react-email-rails/runtime": ${JSON.stringify(runtimeEntry)},`,
        `    },`,
        `  },`,
        `  define: { __EMAIL_NAME__: ${JSON.stringify(JSON.stringify("Ada Lovelace"))} },`,
        `  css: { modules: { localsConvention: "camelCaseOnly" } },`,
        `  build: { outDir: "dist-client" },`,
        `  plugins: [`,
        `    unrelatedHostPlugin(),`,
        `    reactEmailRails({`,
        `      emails: { path: "app/frontend/emails", extension: ".email.tsx", ignore: ["ignored/**"] },`,
        `      standalone: false,`,
        `      vite: {`,
        `        plugins: [emailOnlyPlugin()],`,
        `        build: { outDir: "wrong-email-output" },`,
        `      },`,
        `    }),`,
        `  ],`,
        `})`,
        ``,
      ].join("\n"),
    )
    writeFileSync(join(root, "index.html"), '<div id="app"></div>\n')
    writeFileSync(
      join(root, "app/frontend/emails/shared.tsx"),
      [
        `import "./styles.css"`,
        ``,
        `export function Section({ children }: { children: unknown }) {`,
        `  return <section className="message">{children}</section>`,
        `}`,
        ``,
      ].join("\n"),
    )
    writeFileSync(join(root, "app/frontend/emails/styles.css"), ".message { color: red; }\n")
    writeFileSync(
      join(root, "app/frontend/emails/account_mailer/created.email.tsx"),
      [
        `import { Section } from "@emails/shared"`,
        `import { marker } from "virtual:email-marker"`,
        ``,
        `declare const __EMAIL_NAME__: string`,
        ``,
        `export default function Created() {`,
        `  return <Section>{__EMAIL_NAME__} {marker}</Section>`,
        `}`,
        ``,
      ].join("\n"),
    )
    writeFileSync(
      join(root, "app/frontend/emails/ignored/skipped.email.tsx"),
      `import "this-module-should-not-resolve"\n`,
    )

    await execFile("node", [join(pkgRoot, "bin/build.mjs")], { cwd: root })

    const bundlePath = join(root, "tmp/react-email-rails/emails.js")
    const output = readJavaScriptOutput(join(root, "tmp/react-email-rails"))
    expect(existsSync(bundlePath)).toBe(true)
    expect(existsSync(join(root, "wrong-email-output"))).toBe(false)
    expect(existsSync(join(root, "dist-client/index.html"))).toBe(false)
    expect(output).toContain("Ada Lovelace")
    expect(output).toContain("email-only-plugin-ran")
    expect(output).toContain("@react-email/render")

    const { stdout } = await execFile("node", [bundlePath, "--health"], { cwd: root })
    expect(JSON.parse(stdout)).toMatchObject({ ok: true, protocolVersion: 1 })
  }, 60_000)
})

function readJavaScriptOutput(dir: string): string {
  return readdirSync(dir, { withFileTypes: true })
    .map((entry) => {
      const path = join(dir, entry.name)
      if (entry.isDirectory()) return readJavaScriptOutput(path)
      return entry.name.endsWith(".js") ? readFileSync(path, "utf8") : ""
    })
    .join("\n")
}
