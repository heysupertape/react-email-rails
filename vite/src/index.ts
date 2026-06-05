import { createRequire } from "node:module"

import type { ConfigEnv, Plugin, UserConfig } from "vite"

export type EmailsOption =
  | string
  | {
      path?: string
      extension?: string | string[]
      ignore?: string | string[]
    }

export type ReactEmailRailsOptions = {
  emails?: EmailsOption
  // Editor document renderers, discovered like emails. Off by default.
  documents?: EmailsOption | boolean
  standalone?: boolean
  vite?: ReactEmailRailsViteOptions
}

export type ReactEmailRailsViteOptions = Pick<
  UserConfig,
  "assetsInclude" | "css" | "define" | "esbuild" | "json" | "plugins" | "resolve"
> & {
  oxc?: unknown
}

type SourceMetadata = {
  path: string
  extensions: string[]
  ignore: string[]
}

type PluginMetadata = {
  emails: SourceMetadata
  documents?: SourceMetadata
  standalone: boolean
  outDir: string
  bundleFile: string
}

type Source = {
  path: string
  extensions: string[]
  ignore: string[]
  root: string
  globArg: string
}

const DEFAULT_IGNORE = ["**/_*", "**/_*/**"]
const DEFAULT_EMAIL_PATH = "app/javascript/emails"
const DEFAULT_EMAIL_EXTENSIONS = [".tsx", ".jsx"]
const DEFAULT_DOCUMENT_PATH = "app/javascript/documents"
const DEFAULT_DOCUMENT_EXTENSIONS = [".ts", ".tsx"]

const VIRTUAL_SERVER = "virtual:react-email-rails/server"
const VIRTUAL_MAIN = "virtual:react-email-rails/main"
const RESOLVED_SERVER = `\0${VIRTUAL_SERVER}`
const RESOLVED_MAIN = `\0${VIRTUAL_MAIN}`
const VIRTUAL_MODULE_PATTERN = /virtual:react-email-rails\/(?:server|main)$/

// The dedicated build environment that emits the server-side email bundle.
export const EMAIL_ENVIRONMENT = "email"
// Wire contract: must match the Symbol.for(...) keys the bins read in bin/shared.mjs.
const CONFIG_SYMBOL = Symbol.for("react-email-rails.config")
const VITE_CONFIG_SYMBOL = Symbol.for("react-email-rails.vite")
// Must match Ruby's Configuration::BUNDLE_PATH (check_version_sync.rb asserts it).
const OUT_DIR = "tmp/react-email-rails"
const BUNDLE_FILE = "emails.js"
const require = createRequire(import.meta.url)

// happy-dom (via @tiptap/html) pulls in `ws`, which guards optional native-addon requires behind
// these flags. Setting them lets a standalone (noExternal) build tree-shake the uninstalled
// bufferutil/utf-8-validate requires away; ws's pure-JS path is all the HTML parser needs.
const WS_NATIVE_ADDON_OPT_OUT = {
  "process.env.WS_NO_BUFFER_UTIL": "'1'",
  "process.env.WS_NO_UTF_8_VALIDATE": "'1'",
}

function normalizeSource(
  option: EmailsOption | undefined,
  defaultPath: string,
  defaultExtensions: string[],
): Source {
  const source = typeof option === "string" ? { path: option } : (option ?? {})
  const path = (source.path ?? defaultPath).replace(/^\/|\/$/g, "")
  const rawExtensions =
    source.extension === undefined
      ? defaultExtensions
      : Array.isArray(source.extension)
        ? source.extension
        : [source.extension]
  const extensions = rawExtensions
    .map((extension) => (extension.startsWith(".") ? extension : `.${extension}`))
    .map((extension, index) => ({ extension, index }))
    .sort(
      (left, right) => right.extension.length - left.extension.length || left.index - right.index,
    )
    .map(({ extension }) => extension)

  const root = `/${path}/`
  const pattern =
    extensions.length === 1 ? `${root}**/*${extensions[0]}` : `${root}**/*{${extensions.join(",")}}`
  const ignore =
    source.ignore === undefined
      ? DEFAULT_IGNORE
      : Array.isArray(source.ignore)
        ? source.ignore
        : [source.ignore]
  const globPatterns = [pattern, ...ignore.map((glob) => `!${root}${glob}`)]
  const globArg = JSON.stringify(globPatterns.length === 1 ? globPatterns[0] : globPatterns)

  return { path, extensions, ignore, root, globArg }
}

function optionalPeersAvailable(specifiers: string[]): boolean {
  return specifiers.every((specifier) => {
    try {
      require.resolve(specifier)
      return true
    } catch {
      return false
    }
  })
}

export function reactEmailRails(options: ReactEmailRailsOptions = {}): Plugin {
  const emailSource = normalizeSource(options.emails, DEFAULT_EMAIL_PATH, DEFAULT_EMAIL_EXTENSIONS)
  const documentSource =
    options.documents === undefined || options.documents === false
      ? null
      : normalizeSource(
          options.documents === true ? undefined : options.documents,
          DEFAULT_DOCUMENT_PATH,
          DEFAULT_DOCUMENT_EXTENSIONS,
        )
  const standalone = options.standalone ?? true

  const plugin: Plugin = {
    name: "react-email-rails",

    resolveId: {
      filter: { id: VIRTUAL_MODULE_PATTERN },
      handler(id) {
        if (id === VIRTUAL_SERVER) return RESOLVED_SERVER
        if (id === VIRTUAL_MAIN) return RESOLVED_MAIN
      },
    },

    load: {
      filter: { id: VIRTUAL_MODULE_PATTERN },
      handler(id) {
        if (id === RESOLVED_SERVER) {
          const lines = [`import { buildRegistry, serve } from "react-email-rails/runtime"`]
          const parserPeersAvailable =
            documentSource && optionalPeersAvailable(["@tiptap/html", "happy-dom"])

          if (documentSource) {
            lines.push(
              parserPeersAvailable
                ? `import { composeDocument, createParseDocument } from "react-email-rails/document"`
                : `import { composeDocument, parseDocument } from "react-email-rails/document"`,
            )
            if (parserPeersAvailable) lines.push(`import { generateJSON } from "@tiptap/html"`)
          }

          lines.push(
            `const registry = buildRegistry(import.meta.glob(${emailSource.globArg}), ${JSON.stringify(emailSource.extensions)}, ${JSON.stringify(emailSource.root)})`,
          )

          if (documentSource) {
            lines.push(
              `const documentRegistry = buildRegistry(import.meta.glob(${documentSource.globArg}), ${JSON.stringify(documentSource.extensions)}, ${JSON.stringify(documentSource.root)})`,
              `export const run = () => serve(registry, { registry: documentRegistry, compose: composeDocument, parse: ${parserPeersAvailable ? "createParseDocument(generateJSON)" : "parseDocument"} })`,
            )
          } else {
            lines.push(`export const run = () => serve(registry)`)
          }

          return lines.join("\n")
        }

        if (id === RESOLVED_MAIN) {
          return `import { run } from ${JSON.stringify(VIRTUAL_SERVER)}\nrun()\n`
        }
      },
    },

    config(_config, env: ConfigEnv) {
      // Dedicated `email` build environment: the react-email-rails-build bin builds it with an
      // isolated plugin stack so host plugins can't break email SSR. Standalone builds inline
      // Node deps (so Rails images need no node_modules); dev keeps them external for the runner.
      return {
        environments: {
          [EMAIL_ENVIRONMENT]: {
            ...(standalone && env.command === "build"
              ? { resolve: { noExternal: true }, define: WS_NATIVE_ADDON_OPT_OUT }
              : {}),
            build: {
              ssr: true,
              outDir: OUT_DIR,
              emptyOutDir: true,
              rollupOptions: {
                input: VIRTUAL_MAIN,
                output: { entryFileNames: BUNDLE_FILE },
              },
            },
          },
        },
      }
    },
  }

  const metadata: PluginMetadata = {
    emails: {
      path: emailSource.path,
      extensions: emailSource.extensions,
      ignore: emailSource.ignore,
    },
    ...(documentSource && {
      documents: {
        path: documentSource.path,
        extensions: documentSource.extensions,
        ignore: documentSource.ignore,
      },
    }),
    standalone,
    outDir: OUT_DIR,
    bundleFile: BUNDLE_FILE,
  }

  Object.defineProperty(plugin, CONFIG_SYMBOL, {
    value: {
      ...metadata,
    },
  })
  Object.defineProperty(plugin, VITE_CONFIG_SYMBOL, {
    value: options.vite ?? {},
  })

  return plugin
}

export type {
  EmailModule,
  EmailRegistry,
  EmailRenderOptions,
  RenderedEmail,
  RenderRequest,
  RenderResult,
} from "./runtime.js"
export { RENDER_PROTOCOL_VERSION, VERSION } from "./version.js"
