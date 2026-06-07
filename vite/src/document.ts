import { EmailNode, composeReactEmail } from "@react-email/editor/core"
import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"
import { getSchema, resolveExtensions, type Extensions } from "@tiptap/core"
import type { Editor } from "@tiptap/core"

import type {
  DroppedNode,
  ParseDocumentRequest,
  ParseResult,
  RenderDocumentRequest,
  RenderResult,
} from "./runtime.js"

// Re-exported from runtime.ts (the single source) to keep react-email-rails/document's surface.
export type { DroppedNode, ParseDocumentRequest, RenderDocumentRequest }

export type DocumentRenderer = {
  buildExtensions: (context: unknown) => Extensions
  transformDocument?: (document: unknown, context: unknown) => unknown
  getPreview?: (context: unknown) => string | null
}

// Editor-bundled structural nodes render to null by design. Derive the list from
// the installed editor package so warning filtering tracks version changes.
const STRUCTURAL_NODE_TYPES: ReadonlySet<string> = new Set(
  resolveExtensions([StarterKit, EmailTheming])
    .filter((extension) => extension.type === "node" && !(extension instanceof EmailNode))
    .map((extension) => extension.name),
)

// composeReactEmail renders a node as null when no extension matches or the match isn't an
// EmailNode; mirror that here so warnings catch the silent case (in-schema node, no email renderer).
function collectDroppedNodes(document: unknown, extensions: Extensions): DroppedNode[] {
  const byName = new Map<string, Extensions[number]>()
  for (const extension of extensions) byName.set(extension.name, extension)

  const counts = new Map<string, number>()
  const walk = (content: unknown): void => {
    if (!Array.isArray(content)) return
    for (const node of content) {
      if (!node || typeof node !== "object") continue
      const type = (node as { type?: unknown }).type
      if (typeof type !== "string" || STRUCTURAL_NODE_TYPES.has(type)) continue

      const extension = byName.get(type)
      if (!extension || !(extension instanceof EmailNode)) {
        counts.set(type, (counts.get(type) ?? 0) + 1)
        continue
      }
      walk((node as { content?: unknown }).content)
    }
  }
  walk((document as { content?: unknown }).content)

  return [...counts].map(([type, count]) => ({ type, count }))
}

export type DocumentLoader = DocumentRenderer | (() => Promise<DocumentRenderer>)
export type DocumentRegistry = Record<string, DocumentLoader>

type GenerateJSON = (html: string, extensions: Extensions) => unknown
type RenderMarkdown = (markdown: string) => string | Promise<string>

// Bound at build time by createParseDocument when the peers are bundled; lazy-loaded otherwise.
type ParseDependencies = {
  generateJSON?: GenerateJSON
  renderMarkdown?: RenderMarkdown
}

async function resolveRenderer(
  type: string,
  registry: DocumentRegistry,
): Promise<DocumentRenderer> {
  const loader = registry[type]
  if (!loader) throw new Error(`React email document renderer not found: ${type}`)

  const renderer = typeof loader === "function" ? await loader() : loader
  if (typeof renderer.buildExtensions !== "function") {
    throw new Error(`React email document renderer must export a buildExtensions function: ${type}`)
  }

  return renderer
}

async function loadGenerateJSON(): Promise<GenerateJSON> {
  try {
    const mod = (await import(/* @vite-ignore */ "@tiptap/html")) as {
      generateJSON?: unknown
    }
    if (typeof mod.generateJSON === "function") return mod.generateJSON as GenerateJSON
  } catch (error) {
    throw new Error(
      `@tiptap/html and happy-dom are required to parse HTML documents; install both packages before calling parse (${error instanceof Error ? error.message : "module load failed"})`,
    )
  }

  throw new Error(
    "@tiptap/html is missing the expected generateJSON export; check the installed version",
  )
}

async function loadRenderMarkdown(): Promise<RenderMarkdown> {
  try {
    const mod = (await import(/* @vite-ignore */ "marked")) as {
      marked?: { parse?: (markdown: string) => string | Promise<string> }
    }

    const marked = mod.marked
    if (marked && typeof marked.parse === "function") {
      const parse = marked.parse.bind(marked)
      return (markdown) => parse(markdown)
    }
  } catch (error) {
    throw new Error(
      `marked is required to parse Markdown documents; install it before calling parse with markdown (${error instanceof Error ? error.message : "module load failed"})`,
    )
  }

  throw new Error("marked is missing the expected parse export; check the installed version")
}

// The schema whitelists nodes and attributes but never validates URI protocols, so a
// javascript:/data: href on a link or button reaches content_json unchecked. Allow only safe schemes.
const ALLOWED_URI_SCHEMES: ReadonlySet<string> = new Set(["http", "https", "mailto", "tel"])

// Characters browsers ignore when resolving a scheme (so "java\tscript:" runs as javascript:).
// Built numerically to keep the source free of literal control characters.
const URI_IGNORED_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x00, 0x20],
  [0xa0, 0xa0],
  [0x1680, 0x1680],
  [0x180e, 0x180e],
  [0x2000, 0x2029],
  [0x205f, 0x205f],
  [0x3000, 0x3000],
  [0xfeff, 0xfeff],
]
const escapeCodePoint = (code: number): string => "\\u" + code.toString(16).padStart(4, "0")
const URI_IGNORED_CHARS = new RegExp(
  "[" +
    URI_IGNORED_RANGES.map(([lo, hi]) => escapeCodePoint(lo) + "-" + escapeCodePoint(hi)).join("") +
    "]",
  "g",
)

function hasAllowedUriScheme(uri: string): boolean {
  // No scheme → relative/anchor/query; nothing to neutralize.
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(uri.replace(URI_IGNORED_CHARS, ""))?.[1]

  return scheme === undefined || ALLOWED_URI_SCHEMES.has(scheme.toLowerCase())
}

// Blank disallowed hrefs (link marks and nodes like button) in place; the tree is fresh
// toJSON() output, so mutation is safe.
function neutralizeUnsafeUris(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) neutralizeUnsafeUris(item)
    return
  }

  if (value === null || typeof value !== "object") return

  const node = value as {
    attrs?: Record<string, unknown>
    marks?: unknown
    content?: unknown
  }

  const attrs = node.attrs
  if (attrs && typeof attrs.href === "string" && !hasAllowedUriScheme(attrs.href)) {
    attrs.href = ""
  }

  neutralizeUnsafeUris(node.marks)
  neutralizeUnsafeUris(node.content)
}

// Both inputs converge on HTML: markdown is rendered first, then parsed like any HTML.
async function resolveHtmlInput(
  request: ParseDocumentRequest,
  dependencies: ParseDependencies,
): Promise<string> {
  const hasHtml = request.html !== undefined
  const hasMarkdown = request.markdown !== undefined
  if (hasHtml === hasMarkdown) {
    throw new Error("parse request must include exactly one of `html` or `markdown`")
  }

  if (hasMarkdown) {
    const renderMarkdown = dependencies.renderMarkdown ?? (await loadRenderMarkdown())
    return renderMarkdown(request.markdown as string)
  }

  return request.html as string
}

export async function composeDocument(
  request: RenderDocumentRequest,
  registry: DocumentRegistry,
): Promise<RenderResult> {
  // Fail legibly if the optional editor peers are present but their shape shifted.
  if (
    typeof composeReactEmail !== "function" ||
    typeof resolveExtensions !== "function" ||
    typeof getSchema !== "function"
  ) {
    throw new Error(
      "@react-email/editor or @tiptap/core is missing expected exports (composeReactEmail/resolveExtensions/getSchema); check the installed versions",
    )
  }

  const renderer = await resolveRenderer(request.type, registry)

  const document =
    renderer.transformDocument?.(request.document, request.context) ?? request.document
  const extensions = resolveExtensions(renderer.buildExtensions(request.context))
  const schema = getSchema(extensions)
  const warnings = collectDroppedNodes(document, extensions)

  // The minimal editor composeReactEmail reads, built headless (no DOM, no view).
  // state.doc is required: EmailTheming finds the globalContent theme node through it.
  const editor = {
    getJSON: () => document,
    extensionManager: { extensions },
    schema,
    state: { doc: schema.nodeFromJSON(document) },
  } as unknown as Editor

  // composeReactEmail takes `preview?: string`; omit it rather than pass null.
  const preview = request.preview ?? renderer.getPreview?.(request.context) ?? null
  const params = preview === null ? { editor } : { editor, preview }

  const { html, text } = await composeReactEmail(params)
  return warnings.length > 0 ? { html, text, warnings } : { html, text }
}

export async function parseDocument(
  request: ParseDocumentRequest,
  registry: DocumentRegistry,
  dependencies: ParseDependencies = {},
): Promise<ParseResult> {
  const renderer = await resolveRenderer(request.type, registry)
  const extensions = resolveExtensions(renderer.buildExtensions(request.context))
  const schema = getSchema(extensions)

  const html = await resolveHtmlInput(request, dependencies)
  const parseHTML = dependencies.generateJSON ?? (await loadGenerateJSON())
  const parsed = parseHTML(html, extensions)
  const document = schema.nodeFromJSON(parsed).toJSON()
  neutralizeUnsafeUris(document)

  return { document }
}

export function createParseDocument(generateJSON: GenerateJSON, renderMarkdown?: RenderMarkdown) {
  // Omit renderMarkdown entirely when unset; exactOptionalPropertyTypes forbids passing `undefined`.
  const dependencies: ParseDependencies =
    renderMarkdown === undefined ? { generateJSON } : { generateJSON, renderMarkdown }
  return (request: ParseDocumentRequest, registry: DocumentRegistry): Promise<ParseResult> =>
    parseDocument(request, registry, dependencies)
}
