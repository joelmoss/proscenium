import { join } from 'std/path/mod.ts'
import { cache } from 'cache'

import setup from './setup_plugin.js'
import { httpRegex, readFile, isBareModule, loaderType, resolveImport } from '../../utils.js'

const importKinds = ['import-statement', 'dynamic-import', 'require-call', 'import-rule']

export default setup('resolve', (build, options) => {
  const { runtimeDir, importMap } = options
  const cwd = build.initialOptions.absWorkingDir
  const runtimeCwdAlias = `${cwd}/proscenium-runtime`

  return [
    {
      // Filters for imports starting with `url:http://` or `url:https://`; returning the path
      // without the `url:` prefix, and a namespace of 'url`
      type: 'onResolve',
      filter: /^url:https?:\/\//,
      callback(args) {
        return {
          path: args.path.slice(4),
          namespace: 'url'
        }
      }
    },

    {
      type: 'onResolve',
      filter: /.*/,
      namespace: 'url',
      callback(args) {
        if (!isBareModule(args.path)) {
          return {
            path: new URL(args.path, args.importer).toString(),
            namespace: 'url'
          }
        }
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'url',
      async callback(args) {
        const file = await cache(args.path)
        const contents = await readFile(file.path)

        return { contents, loader: loaderType(args.path) }
      }
    },

    // Catch all resolution.
    {
      type: 'onResolve',
      filter: /.*/,
      async callback(params) {
        if (params.path.includes('?')) {
          const [path, query] = params.path.split('?')
          params.path = path
          params.suffix = `?${query}`
          params.queryParams = new URLSearchParams(query)
        } else if (options.cacheQueryString && options.cacheQueryString !== '') {
          params.suffix = `?${options.cacheQueryString}`
        }

        // Rewrite the path to the actual runtime directory.
        if (params.path.startsWith(runtimeCwdAlias)) {
          return { path: join(runtimeDir, params.path.slice(runtimeCwdAlias.length)) }
        }

        // Everything else is unbundled.
        if (importKinds.includes(params.kind)) {
          const result = await resolveImport(params, build, importMap)
          const isUrl = httpRegex.test(result.path)

          // Internalise if path is outside root, and is not a URL. This will most likely be because
          // it is a link: dependency.
          if (!isUrl && isOutsideRoot(result.path, cwd)) {
            return { ...result, external: false }
          }

          if (
            result.path.endsWith('.css') &&
            params.kind === 'import-statement' &&
            /\.jsx?$/.test(params.importer)
          ) {
            // We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
            // the css plugin to return the CSS as a JS object of class names (css module).
            return { ...result, pluginData: { importedFromJs: true } }
          }

          if (isUrl) {
            // Path is a URL, so add the url prefix, and externalise.
            result.path = `/url:${encodeURIComponent(result.path)}`
          } else {
            // Path is external, so make sure it is an absolute URL path.
            result.path = result.path.slice(cwd.length)
          }

          // Ensure suffix is added.
          if (params.suffix && params.suffix !== '') {
            result.path = `${result.path}${params.suffix}`
          }

          result.external = true
          return result
        }
      }
    }
  ]
})

function isOutsideRoot(path, root) {
  return !path.startsWith(root)
}
