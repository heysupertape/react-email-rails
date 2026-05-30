import type { Plugin } from "vite"

export type EmailsOption =
  | string
  | {
      path?: string
      extension?: string | string[]
      lazy?: boolean
      ignore?: string | string[]
    }

export type ReactEmailRailsOptions = {
  emails?: EmailsOption
  standalone?: boolean
}

const DEFAULT_IGNORE = ["**/_*", "**/_*/**"]
const DEFAULT_EXTENSIONS = [".tsx", ".jsx"]

const VIRTUAL_SERVER = "virtual:react-email-rails/server"
const VIRTUAL_MAIN = "virtual:react-email-rails/main"
const RESOLVED_SERVER = `\0${VIRTUAL_SERVER}`
const RESOLVED_MAIN = `\0${VIRTUAL_MAIN}`

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
    .sort((left, right) => right.extension.length - left.extension.length || left.index - right.index)
    .map(({ extension }) => extension)
  const lazy = emails.lazy ?? true
  const standalone = options.standalone ?? false

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
  const globOptions = lazy ? "" : ", { eager: true }"

  return {
    name: "react-email-rails",

    resolveId(id) {
      if (id === VIRTUAL_SERVER) return RESOLVED_SERVER
      if (id === VIRTUAL_MAIN) return RESOLVED_MAIN
    },

    load(id) {
      if (id === RESOLVED_SERVER) {
        return [
          `import { serve, toComponentName } from "react-email-rails/runtime"`,
          `const modules = import.meta.glob(${globArg}${globOptions})`,
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

    config(_config, { mode }) {
      if (mode !== "email") return

      return {
        ...(standalone ? { ssr: { noExternal: true } } : {}),
        build: {
          ssr: true,
          outDir: "tmp/react-email-rails",
          emptyOutDir: true,
          rollupOptions: {
            input: VIRTUAL_MAIN,
            output: { entryFileNames: "emails.js" },
          },
        },
      }
    },
  }
}

export type {
  EmailModule,
  EmailRegistry,
  EmailRenderOptions,
  RenderedEmail,
  RenderRequest,
} from "./runtime"
