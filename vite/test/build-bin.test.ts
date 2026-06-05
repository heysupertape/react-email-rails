import { execFile as execFileCallback, spawn } from "node:child_process"
import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { promisify } from "node:util"

import { afterAll, describe, expect, it } from "vitest"

import { RENDER_PROTOCOL_VERSION } from "../src/version"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")
const runtimeEntry = join(pkgRoot, "src/runtime.ts")
const documentEntry = join(pkgRoot, "src/document.ts")
const fixtures: string[] = []
const execFile = promisify(execFileCallback)

// Drive a built bundle in one-shot mode: request in on stdin, JSON out on stdout.
function renderWithBundle(bundlePath: string, request: unknown, cwd: string): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const child = spawn("node", [bundlePath], { cwd })
    let stdout = ""
    let stderr = ""
    child.stdout.on("data", (chunk) => (stdout += chunk))
    child.stderr.on("data", (chunk) => (stderr += chunk))
    child.on("error", reject)
    child.on("close", (code) => {
      if (code !== 0) return reject(new Error(stderr || `bundle exited with ${code}`))
      try {
        resolve(JSON.parse(stdout))
      } catch {
        reject(new Error(`bundle returned invalid JSON: ${stdout}\n${stderr}`))
      }
    })
    child.stdin.write(JSON.stringify(request))
    child.stdin.end()
  })
}

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
    expect(JSON.parse(stdout)).toMatchObject({ ok: true, protocolVersion: RENDER_PROTOCOL_VERSION })
  }, 60_000)

  it("emits a standalone email bundle by default", async () => {
    const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-build-bin-standalone-"))
    const isolated = mkdtempSync(join(tmpdir(), "rer-standalone-"))
    fixtures.push(root, isolated)

    mkdirSync(join(root, "app/frontend/emails/account_mailer"), { recursive: true })
    writeFileSync(
      join(root, "vite.config.ts"),
      [
        `import { defineConfig } from "vite"`,
        `import { reactEmailRails } from ${JSON.stringify(
          pathToFileURL(join(pkgRoot, "dist/index.js")).href,
        )}`,
        ``,
        `export default defineConfig({`,
        `  resolve: { alias: { "react-email-rails/runtime": ${JSON.stringify(runtimeEntry)} } },`,
        `  plugins: [reactEmailRails({ emails: "app/frontend/emails" })],`,
        `})`,
        ``,
      ].join("\n"),
    )
    writeFileSync(
      join(root, "app/frontend/emails/account_mailer/created.tsx"),
      [
        `import { createElement } from "react"`,
        ``,
        `export default function Created() {`,
        `  return createElement("p", null, "Standalone")`,
        `}`,
        ``,
      ].join("\n"),
    )

    await execFile("node", [join(pkgRoot, "bin/build.mjs")], { cwd: root })

    const bundlePath = join(root, "tmp/react-email-rails/emails.js")
    const isolatedBundlePath = join(isolated, "emails.js")
    copyFileSync(bundlePath, isolatedBundlePath)

    const { stdout } = await execFile("node", [isolatedBundlePath, "--health"], { cwd: isolated })
    expect(JSON.parse(stdout)).toMatchObject({ ok: true, protocolVersion: RENDER_PROTOCOL_VERSION })
  }, 60_000)

  it("renders and parses editor documents from a standalone bundle with tiptap inlined", async () => {
    const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-build-bin-documents-"))
    const isolated = mkdtempSync(join(tmpdir(), "rer-documents-"))
    fixtures.push(root, isolated)

    mkdirSync(join(root, "app/frontend/emails/account_mailer"), { recursive: true })
    mkdirSync(join(root, "app/frontend/documents"), { recursive: true })
    writeFileSync(
      join(root, "vite.config.ts"),
      [
        `import { defineConfig } from "vite"`,
        `import { reactEmailRails } from ${JSON.stringify(
          pathToFileURL(join(pkgRoot, "dist/index.js")).href,
        )}`,
        ``,
        `export default defineConfig({`,
        `  resolve: { alias: {`,
        `    "react-email-rails/runtime": ${JSON.stringify(runtimeEntry)},`,
        `    "react-email-rails/document": ${JSON.stringify(documentEntry)},`,
        `  } },`,
        `  plugins: [reactEmailRails({`,
        `    emails: "app/frontend/emails",`,
        `    documents: "app/frontend/documents",`,
        `  })],`,
        `})`,
        ``,
      ].join("\n"),
    )
    // An email still has to build alongside the document renderer.
    writeFileSync(
      join(root, "app/frontend/emails/account_mailer/created.tsx"),
      [
        `import { createElement } from "react"`,
        ``,
        `export default function Created() {`,
        `  return createElement("p", null, "Standalone")`,
        `}`,
        ``,
      ].join("\n"),
    )
    writeFileSync(
      join(root, "app/frontend/documents/broadcast.ts"),
      [
        `import { StarterKit } from "@react-email/editor/extensions"`,
        `import { EmailTheming } from "@react-email/editor/plugins"`,
        ``,
        `export function buildExtensions() {`,
        `  return [StarterKit, EmailTheming]`,
        `}`,
        ``,
      ].join("\n"),
    )

    await execFile("node", [join(pkgRoot, "bin/build.mjs")], { cwd: root })

    // The output is a directory (emails.js + lazily-split chunks); copy it all
    // somewhere without node_modules to prove tiptap/editor/prosemirror are inlined.
    cpSync(join(root, "tmp/react-email-rails"), isolated, { recursive: true })
    const isolatedBundlePath = join(isolated, "emails.js")

    const document = {
      type: "doc",
      content: [
        { type: "globalContent", attrs: {} },
        {
          type: "heading",
          attrs: { level: 1 },
          content: [{ type: "text", text: "Broadcast headline" }],
        },
      ],
    }
    const response = (await renderWithBundle(
      isolatedBundlePath,
      { kind: "document", type: "broadcast", document, preview: "Inbox preview" },
      isolated,
    )) as { html: string; text: string; protocolVersion: number }

    expect(response.protocolVersion).toBe(RENDER_PROTOCOL_VERSION)
    expect(response.html).toContain("Broadcast headline")
    expect(response.html).toContain("Inbox preview")
    expect(response.text).toMatch(/broadcast headline/i)

    const parsed = (await renderWithBundle(
      isolatedBundlePath,
      { kind: "parse", type: "broadcast", html: "<h1>Parsed headline</h1><p>From HTML</p>" },
      isolated,
    )) as { document: { type: string; content: { type: string }[] }; protocolVersion: number }

    expect(parsed.protocolVersion).toBe(RENDER_PROTOCOL_VERSION)
    expect(parsed.document.type).toBe("doc")
    expect(parsed.document.content.some((node) => node.type === "heading")).toBe(true)

    const rendered = (await renderWithBundle(
      isolatedBundlePath,
      { kind: "document", type: "broadcast", document: parsed.document },
      isolated,
    )) as { html: string }

    expect(rendered.html).toContain("Parsed headline")
    expect(rendered.html).toContain("From HTML")
  }, 90_000)
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
