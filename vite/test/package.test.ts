import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

import { describe, expect, it } from "vitest"

const pkgRoot = join(dirname(fileURLToPath(import.meta.url)), "..")

describe("package metadata", () => {
  const pkg = JSON.parse(readFileSync(join(pkgRoot, "package.json"), "utf8")) as {
    dependencies?: Record<string, string>
    peerDependencies?: Record<string, string>
  }

  it("declares Vite 7 and Vite 8 as supported peers", () => {
    expect(pkg.peerDependencies?.vite).toBe("^7.0.0 || ^8.0.0")
  })

  it("keeps React and ReactDOM as peers shared with the host application", () => {
    expect(pkg.peerDependencies?.react).toBe("^18.0 || ^19.0")
    expect(pkg.peerDependencies?.["react-dom"]).toBe("^18.0 || ^19.0")
  })

  it("owns @react-email/render as a runtime dependency, not a peer", () => {
    expect(pkg.dependencies?.["@react-email/render"]).toBe("^2.1.0")
    expect(pkg.peerDependencies).not.toHaveProperty("@react-email/render")
  })
})
