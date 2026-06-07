import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"
import { Node } from "@tiptap/core"
import { describe, expect, it } from "vitest"

import { marked } from "marked"

import {
  composeDocument,
  createParseDocument,
  type DocumentRegistry,
  type DocumentRenderer,
  parseDocument,
} from "../src/document"

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

  it("reports no warnings when every node renders, ignoring the theme node", async () => {
    const result = await composeDocument(request("broadcast"), { broadcast })

    expect(result.warnings).toBeUndefined()
  })

  it("reports node types dropped because no extension renders them", async () => {
    // A plain Tiptap node is in the schema (so nodeFromJSON succeeds) but is not
    // an EmailNode, so the serializer renders it as null — the silent-drop case.
    const customBlock = Node.create({ name: "customBlock", group: "block", content: "text*" })
    const registry: DocumentRegistry = {
      broadcast: { buildExtensions: () => [StarterKit, EmailTheming, customBlock] },
    }
    const document = {
      type: "doc",
      content: [
        { type: "globalContent", attrs: {} },
        { type: "customBlock", content: [{ type: "text", text: "dropped one" }] },
        { type: "customBlock", content: [{ type: "text", text: "dropped two" }] },
        { type: "paragraph", content: [{ type: "text", text: "kept" }] },
      ],
    }

    const result = await composeDocument(
      { kind: "document", type: "broadcast", document },
      registry,
    )

    expect(result.warnings).toEqual([{ type: "customBlock", count: 2 }])
    expect(result.html).not.toContain("dropped one")
    expect(result.html).toContain("kept")
  })
})

describe("parseDocument", () => {
  function parse(type: string, html: string, context?: unknown) {
    return {
      kind: "parse" as const,
      type,
      html,
      ...(context === undefined ? {} : { context }),
    }
  }

  it("parses HTML into an editor document (Tiptap JSON)", async () => {
    const result = await parseDocument(parse("broadcast", "<h1>Hello world</h1><p>Body copy</p>"), {
      broadcast,
    })

    const document = result.document as JSONNode
    expect(document.type).toBe("doc")
    const types = (document.content ?? []).map((node) => node.type)
    expect(types).toContain("heading")
    expect(types).toContain("paragraph")
  })

  it("produces a document that composes identically to editor-authored JSON", async () => {
    const parsed = await parseDocument(parse("broadcast", "<h1>Headline</h1><p>Body</p>"), {
      broadcast,
    })

    const authored: JSONNode = {
      type: "doc",
      content: [
        { type: "heading", attrs: { level: 1 }, content: [{ type: "text", text: "Headline" }] },
        { type: "paragraph", content: [{ type: "text", text: "Body" }] },
      ],
    }

    const fromParsed = await composeDocument(
      { kind: "document", type: "broadcast", document: parsed.document },
      { broadcast },
    )
    const fromAuthored = await composeDocument(
      { kind: "document", type: "broadcast", document: authored },
      { broadcast },
    )

    expect(fromParsed.html).toBe(fromAuthored.html)
    expect(fromParsed.text).toBe(fromAuthored.text)
  })

  it("returns a canonical document that round-trips unchanged", async () => {
    const first = await parseDocument(parse("broadcast", "<p>Stable</p>"), { broadcast })
    const second = await parseDocument(parse("broadcast", "<p>Stable</p>"), { broadcast })

    expect(second.document).toEqual(first.document)
  })

  it("throws when the renderer is not found", async () => {
    await expect(parseDocument(parse("missing", "<p>x</p>"), {})).rejects.toThrow(
      "document renderer not found: missing",
    )
  })

  it("throws when the renderer does not export buildExtensions", async () => {
    const registry = { broken: {} as DocumentRenderer }

    await expect(parseDocument(parse("broken", "<p>x</p>"), registry)).rejects.toThrow(
      "buildExtensions",
    )
  })

  it("passes context to buildExtensions", async () => {
    let seen: unknown
    const registry: DocumentRegistry = {
      broadcast: {
        buildExtensions: (context) => {
          seen = context
          return [StarterKit, EmailTheming]
        },
      },
    }

    await parseDocument(parse("broadcast", "<p>x</p>", { brand: "Acme" }), registry)

    expect(seen).toEqual({ brand: "Acme" })
  })

  it("throws when neither html nor markdown is provided", async () => {
    await expect(
      parseDocument({ kind: "parse", type: "broadcast" }, { broadcast }),
    ).rejects.toThrow("exactly one of")
  })

  it("throws when both html and markdown are provided", async () => {
    await expect(
      parseDocument(
        { kind: "parse", type: "broadcast", html: "<p>x</p>", markdown: "x" },
        { broadcast },
      ),
    ).rejects.toThrow("exactly one of")
  })
})

describe("parseDocument with markdown", () => {
  function parse(type: string, markdown: string, context?: unknown) {
    return {
      kind: "parse" as const,
      type,
      markdown,
      ...(context === undefined ? {} : { context }),
    }
  }

  it("parses Markdown into an editor document (Tiptap JSON)", async () => {
    const result = await parseDocument(parse("broadcast", "# Hello world\n\nBody copy"), {
      broadcast,
    })

    const document = result.document as JSONNode
    expect(document.type).toBe("doc")
    const types = (document.content ?? []).map((node) => node.type)
    expect(types).toContain("heading")
    expect(types).toContain("paragraph")
  })

  it("produces the same document as the equivalent HTML", async () => {
    const fromMarkdown = await parseDocument(parse("broadcast", "# Headline\n\nBody"), {
      broadcast,
    })
    const fromHtml = await parseDocument(
      { kind: "parse", type: "broadcast", html: "<h1>Headline</h1><p>Body</p>" },
      { broadcast },
    )

    expect(fromMarkdown.document).toEqual(fromHtml.document)
  })

  it("renders Markdown emphasis into marks", async () => {
    const result = await parseDocument(parse("broadcast", "A **bold** word"), { broadcast })

    const fromMarkdown = await composeDocument(
      { kind: "document", type: "broadcast", document: result.document },
      { broadcast },
    )

    expect(fromMarkdown.html).toContain("bold")
    expect(fromMarkdown.html).toMatch(/<strong|font-weight/i)
  })

  it("uses an injected markdown renderer (createParseDocument)", async () => {
    const { generateJSON } = await import("@tiptap/html")
    const renderMarkdown = (md: string) => marked.parse(md, { async: false })
    const composedParse = createParseDocument(generateJSON, renderMarkdown)

    const result = await composedParse(parse("broadcast", "# Injected"), { broadcast })

    const document = result.document as JSONNode
    expect((document.content ?? []).map((node) => node.type)).toContain("heading")
  })

  it("passes context to buildExtensions", async () => {
    let seen: unknown
    const registry: DocumentRegistry = {
      broadcast: {
        buildExtensions: (context) => {
          seen = context
          return [StarterKit, EmailTheming]
        },
      },
    }

    await parseDocument(parse("broadcast", "# Hi", { brand: "Acme" }), registry)

    expect(seen).toEqual({ brand: "Acme" })
  })
})

describe("parseDocument neutralizes unsafe URIs", () => {
  function collectHrefs(value: unknown, out: string[] = []): string[] {
    if (Array.isArray(value)) {
      for (const item of value) collectHrefs(item, out)
      return out
    }
    if (value === null || typeof value !== "object") return out

    const node = value as { attrs?: { href?: unknown }; marks?: unknown; content?: unknown }
    if (typeof node.attrs?.href === "string") out.push(node.attrs.href)
    collectHrefs(node.marks, out)
    collectHrefs(node.content, out)
    return out
  }

  function html(type: string, source: string) {
    return { kind: "parse" as const, type, html: source }
  }

  it("blanks a javascript: href from the html: input", async () => {
    const result = await parseDocument(
      html("broadcast", '<p><a href="javascript:alert(1)">click</a></p>'),
      { broadcast },
    )

    expect(collectHrefs(result.document)).toEqual([""])
  })

  it("blanks a javascript: link from the markdown: input", async () => {
    const result = await parseDocument(
      { kind: "parse", type: "broadcast", markdown: "[click](javascript:alert(1))" },
      { broadcast },
    )

    expect(collectHrefs(result.document)).toEqual([""])
  })

  it("blanks a data: href", async () => {
    const result = await parseDocument(
      html("broadcast", '<p><a href="data:text/html,<script>alert(1)</script>">x</a></p>'),
      { broadcast },
    )

    expect(collectHrefs(result.document)).toEqual([""])
  })

  it("preserves safe schemes and scheme-less URLs", async () => {
    const source =
      "<p>" +
      '<a href="https://example.com">a</a>' +
      '<a href="mailto:a@b.com">b</a>' +
      '<a href="tel:+15551234">c</a>' +
      '<a href="/relative/path">d</a>' +
      '<a href="#anchor">e</a>' +
      "</p>"
    const result = await parseDocument(html("broadcast", source), { broadcast })

    expect(collectHrefs(result.document)).toEqual([
      "https://example.com",
      "mailto:a@b.com",
      "tel:+15551234",
      "/relative/path",
      "#anchor",
    ])
  })

  it("defangs case- and whitespace-obfuscated schemes", async () => {
    const source =
      "<p>" +
      '<a href="JaVaScRiPt:alert(1)">a</a>' +
      '<a href="  javascript:alert(1)">b</a>' +
      '<a href="java\tscript:alert(1)">c</a>' +
      "</p>"
    const result = await parseDocument(html("broadcast", source), { broadcast })

    expect(collectHrefs(result.document)).toEqual(["", "", ""])
  })

  it("defangs an entity-encoded colon that the parser decodes into a scheme", async () => {
    const result = await parseDocument(
      html("broadcast", '<p><a href="javascript&#58;alert(1)">x</a></p>'),
      { broadcast },
    )

    expect(collectHrefs(result.document)).toEqual([""])
  })

  it("emits no dangerous scheme when the sanitized document is rendered", async () => {
    const parsed = await parseDocument(
      html("broadcast", '<p><a href="javascript:alert(1)">danger</a></p>'),
      { broadcast },
    )

    const composed = await composeDocument(
      { kind: "document", type: "broadcast", document: parsed.document },
      { broadcast },
    )

    expect(composed.html).not.toContain("javascript:")
    expect(composed.html).toContain("danger")
  })
})
