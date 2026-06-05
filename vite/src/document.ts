import { EmailNode, composeReactEmail } from "@react-email/editor/core"
import { StarterKit } from "@react-email/editor/extensions"
import { EmailTheming } from "@react-email/editor/plugins"
import { getSchema, resolveExtensions, type Extensions } from "@tiptap/core"
import type { Editor } from "@tiptap/core"

import type { DroppedNode, ParseResult, RenderResult } from "./runtime.js"

export type { DroppedNode }

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

// composeReactEmail renders a node as null when no extension matches its type or
// the match is not an EmailNode. Mirror that predicate over the document so
// warnings report the silent case: an in-schema node with no email renderer.
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

export type RenderDocumentRequest = {
  kind: "document"
  type: string
  document: unknown
  context?: unknown
  preview?: string | null
}

export type ParseDocumentRequest = {
  kind: "parse"
  type: string
  html: string
  context?: unknown
}

type GenerateJSON = (html: string, extensions: Extensions) => unknown

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
  generateJSON?: GenerateJSON,
): Promise<ParseResult> {
  const parseHTML = generateJSON ?? (await loadGenerateJSON())
  const renderer = await resolveRenderer(request.type, registry)
  const extensions = resolveExtensions(renderer.buildExtensions(request.context))
  const schema = getSchema(extensions)

  const parsed = parseHTML(request.html, extensions)
  const document = schema.nodeFromJSON(parsed).toJSON()

  return { document }
}

export function createParseDocument(generateJSON: GenerateJSON) {
  return (request: ParseDocumentRequest, registry: DocumentRegistry): Promise<ParseResult> =>
    parseDocument(request, registry, generateJSON)
}
