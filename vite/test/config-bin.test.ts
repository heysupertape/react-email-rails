import { execFile as execFileCallback } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"
import { promisify } from "node:util"

import { afterAll, describe, expect, it } from "vitest"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")
const fixtures: string[] = []
const execFile = promisify(execFileCallback)

afterAll(() => {
  for (const dir of fixtures) rmSync(dir, { recursive: true, force: true })
})

describe("react-email-rails-config", () => {
  it("loads the user Vite config and prints plugin metadata", async () => {
    const root = mkdtempSync(join(pkgRoot, "node_modules", ".rer-config-"))
    fixtures.push(root)

    writeFileSync(
      join(root, "vite.config.ts"),
      [
        `import { defineConfig } from "vite"`,
        `import { reactEmailRails } from ${JSON.stringify(
          pathToFileURL(join(pkgRoot, "src/index.ts")).href,
        )}`,
        ``,
        `export default defineConfig({`,
        `  plugins: [reactEmailRails({ emails: { path: "app/frontend/emails", extension: "jsx" }, standalone: false })],`,
        `})`,
        ``,
      ].join("\n"),
    )

    const { stdout } = await execFile("node", [join(pkgRoot, "bin/config.mjs")], { cwd: root })

    expect(JSON.parse(stdout)).toMatchObject({
      emails: {
        path: "app/frontend/emails",
        extensions: [".jsx"],
      },
      standalone: false,
    })
  })
})
