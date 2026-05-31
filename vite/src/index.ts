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
  standalone?: boolean
  vite?: ReactEmailRailsViteOptions
}

export type ReactEmailRailsViteOptions = Pick<
  UserConfig,
  "assetsInclude" | "css" | "define" | "esbuild" | "json" | "plugins" | "resolve"
> & {
  oxc?: unknown
}

type PluginMetadata = {
  emails: {
    path: string
    extensions: string[]
    ignore: string[]
  }
  standalone: boolean
  outDir: string
  bundleFile: string
}

const DEFAULT_IGNORE = ["**/_*", "**/_*/**"]
const DEFAULT_EXTENSIONS = [".tsx", ".jsx"]

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

export function reactEmailRails(options: ReactEmailRailsOptions = {}): Plugin {
  const emails =
    typeof options.emails === "string" ? { path: options.emails } : (options.emails ?? {})
  const path = (emails.path ?? "app/javascript/emails").replace(/^\/|\/$/g, "")
  const rawExtensions =
    emails.extension === undefined
      ? DEFAULT_EXTENSIONS
      : Array.isArray(emails.extension)
        ? emails.extension
        : [emails.extension]
  const extensions = rawExtensions
    .map((extension) => (extension.startsWith(".") ? extension : `.${extension}`))
    .map((extension, index) => ({ extension, index }))
    .sort(
      (left, right) => right.extension.length - left.extension.length || left.index - right.index,
    )
    .map(({ extension }) => extension)
  const standalone = options.standalone ?? true

  const root = `/${path}/`
  const pattern =
    extensions.length === 1 ? `${root}**/*${extensions[0]}` : `${root}**/*{${extensions.join(",")}}`
  const ignore =
    emails.ignore === undefined
      ? DEFAULT_IGNORE
      : Array.isArray(emails.ignore)
        ? emails.ignore
        : [emails.ignore]
  const globPatterns = [pattern, ...ignore.map((glob) => `!${root}${glob}`)]
  const globArg = JSON.stringify(globPatterns.length === 1 ? globPatterns[0] : globPatterns)

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
          return [
            `import { serve, toComponentName } from "react-email-rails/runtime"`,
            `const modules = import.meta.glob(${globArg})`,
            `const extensions = ${JSON.stringify(extensions)}`,
            `const registry = Object.create(null)`,
            `for (const path in modules) {`,
            `  const extension = extensions.find((extension) => path.endsWith(extension)) ?? path.slice(path.lastIndexOf("."))`,
            `  registry[toComponentName(path, ${JSON.stringify(root)}, extension)] = modules[path]`,
            `}`,
            `export const run = () => serve(registry)`,
          ].join("\n")
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
            ...(standalone && env.command === "build" ? { resolve: { noExternal: true } } : {}),
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
      path,
      extensions,
      ignore,
    },
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
} from "./runtime.js"
export { RENDER_PROTOCOL_VERSION, VERSION } from "./version.js"
