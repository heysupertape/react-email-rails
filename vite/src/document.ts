import { composeReactEmail } from "@react-email/editor/core"
import { getSchema, resolveExtensions, type Extensions } from "@tiptap/core"
import type { Editor } from "@tiptap/core"

import type { RenderedEmail } from "./runtime.js"

export type DocumentRenderer = {
  buildExtensions: (context: unknown) => Extensions
  transformDocument?: (document: unknown, context: unknown) => unknown
  getPreview?: (context: unknown) => string | null
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

export async function composeDocument(
  request: RenderDocumentRequest,
  registry: DocumentRegistry,
): Promise<RenderedEmail> {
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

  const loader = registry[request.type]
  if (!loader) throw new Error(`React email document renderer not found: ${request.type}`)

  const renderer = typeof loader === "function" ? await loader() : loader
  if (typeof renderer.buildExtensions !== "function") {
    throw new Error(
      `React email document renderer must export a buildExtensions function: ${request.type}`,
    )
  }

  const document =
    renderer.transformDocument?.(request.document, request.context) ?? request.document
  const extensions = resolveExtensions(renderer.buildExtensions(request.context))
  const schema = getSchema(extensions)

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
  return { html, text }
}
