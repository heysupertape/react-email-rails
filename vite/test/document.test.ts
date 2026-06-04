import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"
import { describe, expect, it } from "vitest"

import { composeDocument, type DocumentRegistry, type DocumentRenderer } from "../src/document"

type JSONNode = {
  type: string
  attrs?: Record<string, unknown>
  content?: JSONNode[]
  text?: string
}

const baseDoc: JSONNode = {
  type: "doc",
  content: [
    // The editor persists its theme here; EmailTheming reads it from state.doc.
    { type: "globalContent", attrs: {} },
    { type: "heading", attrs: { level: 1 }, content: [{ type: "text", text: "Hello world" }] },
    { type: "paragraph", content: [{ type: "text", text: "Body copy" }] },
  ],
}

const broadcast: DocumentRenderer = { buildExtensions: () => [StarterKit, EmailTheming] }

function request(type: string, document: unknown = baseDoc, preview?: string) {
  return {
    kind: "document" as const,
    type,
    document,
    ...(preview === undefined ? {} : { preview }),
  }
}

describe("composeDocument", () => {
  it("renders a document to html and text", async () => {
    const registry: DocumentRegistry = { broadcast }

    const result = await composeDocument(request("broadcast"), registry)

    expect(result.html).toContain("Hello world")
    expect(result.html).toContain("Body copy")
    expect(result.text).toMatch(/hello world/i)
  })

  it("resolves a lazy loader entry", async () => {
    const registry: DocumentRegistry = { broadcast: async () => broadcast }

    const result = await composeDocument(request("broadcast"), registry)

    expect(result.html).toContain("Hello world")
  })

  it("throws when the renderer is not found", async () => {
    await expect(composeDocument(request("missing"), {})).rejects.toThrow(
      "document renderer not found: missing",
    )
  })

  it("throws when the renderer does not export buildExtensions", async () => {
    const registry = { broken: {} as DocumentRenderer }

    await expect(composeDocument(request("broken"), registry)).rejects.toThrow("buildExtensions")
  })

  it("applies transformDocument before rendering", async () => {
    const registry: DocumentRegistry = {
      broadcast: {
        buildExtensions: () => [StarterKit, EmailTheming],
        transformDocument: (document) => {
          const doc = document as JSONNode
          const [theme, ...rest] = doc.content ?? []
          return {
            ...doc,
            content: [
              theme,
              {
                type: "heading",
                attrs: { level: 1 },
                content: [{ type: "text", text: "Injected header" }],
              },
              ...rest,
            ],
          }
        },
      },
    }

    const result = await composeDocument(request("broadcast"), registry)

    expect(result.html).toContain("Injected header")
    expect(result.html).toContain("Hello world")
  })

  it("falls back to getPreview when the request omits a preview", async () => {
    const registry: DocumentRegistry = {
      broadcast: {
        buildExtensions: () => [StarterKit, EmailTheming],
        getPreview: () => "Preview from renderer",
      },
    }

    const result = await composeDocument(request("broadcast"), registry)

    expect(result.html).toContain("Preview from renderer")
  })

  it("prefers the request preview over getPreview", async () => {
    const registry: DocumentRegistry = {
      broadcast: {
        buildExtensions: () => [StarterKit, EmailTheming],
        getPreview: () => "Preview from renderer",
      },
    }

    const result = await composeDocument(
      request("broadcast", baseDoc, "Preview from request"),
      registry,
    )

    expect(result.html).toContain("Preview from request")
    expect(result.html).not.toContain("Preview from renderer")
  })

  it("passes context to buildExtensions, transformDocument, and getPreview", async () => {
    const seen: Record<string, unknown> = {}
    const registry: DocumentRegistry = {
      broadcast: {
        buildExtensions: (context) => {
          seen.build = context
          return [StarterKit, EmailTheming]
        },
        transformDocument: (document, context) => {
          seen.transform = context
          return document
        },
        getPreview: (context) => {
          seen.preview = context
          return null
        },
      },
    }

    await composeDocument(
      { kind: "document", type: "broadcast", document: baseDoc, context: { brand: "Acme" } },
      registry,
    )

    expect(seen.build).toEqual({ brand: "Acme" })
    expect(seen.transform).toEqual({ brand: "Acme" })
    expect(seen.preview).toEqual({ brand: "Acme" })
  })
})
