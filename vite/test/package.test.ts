import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

import { describe, expect, it } from "vitest"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")

describe("package metadata", () => {
  it("declares Vite 7 and Vite 8 as supported peers", () => {
    const pkg = JSON.parse(readFileSync(join(pkgRoot, "package.json"), "utf8")) as {
      peerDependencies?: Record<string, string>
    }

    expect(pkg.peerDependencies?.vite).toBe("^7.0.0 || ^8.0.0")
  })

  it("keeps root and runtime declarations free of document-only optional peers", () => {
    const indexTypes = readFileSync(join(pkgRoot, "dist/index.d.ts"), "utf8")
    const runtimeTypes = readFileSync(join(pkgRoot, "dist/runtime.d.ts"), "utf8")

    expect(indexTypes).not.toContain("./document")
    expect(runtimeTypes).not.toContain("./document")
    expect(runtimeTypes).not.toContain("@react-email/editor")
    expect(runtimeTypes).not.toContain("@tiptap/core")
  })
})
