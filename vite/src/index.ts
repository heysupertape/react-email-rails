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
  // Editor document renderers, discovered like emails. Off by default; pass `true`
  // to enable with defaults, or a path/options object to customize discovery.
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
const CONFIG_SYMBOL = Symbol.for("react-email-rails.config")
const VITE_CONFIG_SYMBOL = Symbol.for("react-email-rails.vite")
const OUT_DIR = "tmp/react-email-rails"
const BUNDLE_FILE = "emails.js"
const require = createRequire(import.meta.url)

// happy-dom (pulled in by @tiptap/html when parsing) depends on `ws`, which guards
// optional native-addon requires behind these env flags. A standalone (noExternal)
// build would otherwise try to bundle the uninstalled `bufferutil`/`utf-8-validate`
// and fail at load. Setting the flags lets Rollup tree-shake those require branches
// away; ws uses its pure-JS implementation, which is all the HTML parser needs.
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
          const lines = [`import { serve, toComponentName } from "react-email-rails/runtime"`]
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
            `const modules = import.meta.glob(${emailSource.globArg})`,
            `const extensions = ${JSON.stringify(emailSource.extensions)}`,
            `const registry = Object.create(null)`,
            `for (const path in modules) {`,
            `  const extension = extensions.find((extension) => path.endsWith(extension)) ?? path.slice(path.lastIndexOf("."))`,
            `  registry[toComponentName(path, ${JSON.stringify(emailSource.root)}, extension)] = modules[path]`,
            `}`,
          )

          if (documentSource) {
            lines.push(
              `const documentModules = import.meta.glob(${documentSource.globArg})`,
              `const documentExtensions = ${JSON.stringify(documentSource.extensions)}`,
              `const documentRegistry = Object.create(null)`,
              `for (const path in documentModules) {`,
              `  const extension = documentExtensions.find((extension) => path.endsWith(extension)) ?? path.slice(path.lastIndexOf("."))`,
              `  documentRegistry[toComponentName(path, ${JSON.stringify(documentSource.root)}, extension)] = documentModules[path]`,
              `}`,
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
      // Register a dedicated `email` build environment. The official
      // react-email-rails-build bin opts into building it with an isolated
      // plugin stack so host app plugins cannot break email SSR builds.
      // The environment is a server consumer. Production standalone builds inline
      // Node dependencies by default so Rails runtime images do not need
      // node_modules; dev rendering keeps dependencies external for Vite's module
      // runner.
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
