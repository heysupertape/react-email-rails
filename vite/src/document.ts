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

export type { DroppedNode, ParseDocumentRequest, RenderDocumentRequest }

export type DocumentRenderer = {
  buildExtensions: (context: unknown) => Extensions
  transformDocument?: (document: unknown, context: unknown) => unknown
  getPreview?: (context: unknown) => string | null
}

const STRUCTURAL_NODE_TYPES: ReadonlySet<string> = new Set(
  resolveExtensions([StarterKit, EmailTheming])
    .filter((extension) => extension.type === "node" && !(extension instanceof EmailNode))
    .map((extension) => extension.name),
)

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

const ALLOWED_URI_SCHEMES: ReadonlySet<string> = new Set(["http", "https", "mailto", "tel"])

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
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(uri.replace(URI_IGNORED_CHARS, ""))?.[1]

  return scheme === undefined || ALLOWED_URI_SCHEMES.has(scheme.toLowerCase())
}

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

  const editor = {
    getJSON: () => document,
    extensionManager: { extensions },
    schema,
    state: { doc: schema.nodeFromJSON(document) },
  } as unknown as Editor

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
  const dependencies: ParseDependencies =
    renderMarkdown === undefined ? { generateJSON } : { generateJSON, renderMarkdown }
  return (request: ParseDocumentRequest, registry: DocumentRegistry): Promise<ParseResult> =>
    parseDocument(request, registry, dependencies)
}
