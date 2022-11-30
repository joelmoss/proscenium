import { join, resolve } from 'std/path/mod.ts'
import resolveFromImportMap from './import_map/resolver.js'
import { cache } from 'cache'

import setup from './setup_plugin.js'
import { isBareModule } from '../../utils.js'

const importKinds = ['import-statement', 'dynamic-import', 'require-call', 'import-rule']

export default setup('resolve', (build, options) => {
  const { runtimeDir, importMap } = options
  const cwd = build.initialOptions.absWorkingDir
  const runtimeCwdAlias = `${cwd}/proscenium-runtime`
  let bundled = false

  const env = Deno.env.get('RAILS_ENV')
  const isProd = env === 'production'

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
        const contents = await Deno.readTextFile(file.path)

        return { contents }
      }
    },

    {
      type: 'onResolve',
      filter: /.*/,
      async callback(args) {
        if (args.path.includes('?')) {
          const [path, query] = args.path.split('?')
          args.path = path
          args.suffix = `?${query}`
          args.queryParams = new URLSearchParams(query)
        } else if (options.cacheQueryString && options.cacheQueryString !== '') {
          args.suffix = `?${options.cacheQueryString}`
        }

        // Mark remote modules as external. If not css, then the path is prefixed with "url:", which
        // is then handled by the Url Middleware.
        if (
          !args.importer.endsWith('.css') &&
          (args.path.startsWith('http://') || args.path.startsWith('https://'))
        ) {
          return { path: `/url:${encodeURIComponent(args.path)}`, external: true }
        }

        // Rewrite the path to the actual runtime directory.
        if (args.path.startsWith(runtimeCwdAlias)) {
          return { path: join(runtimeDir, args.path.slice(runtimeCwdAlias.length)) }
        }

        // Everything else is unbundled.
        if (importKinds.includes(args.kind)) {
          return await unbundleImport(args)
        }
      }
    }
  ]

  // Resolve the given `params.path` to a path relative to the Rails root.
  //
  // Examples:
  //  'react' -> '/.../node_modules/react/index.js'
  //  './my_module' -> '/.../app/my_module.js'
  //  '/app/my_module' -> '/.../app/my_module.js'
  async function unbundleImport(params) {
    const result = { path: params.path, suffix: params.suffix }

    if (importMap) {
      let baseURL
      if (params.importer.startsWith('https://') || params.importer.startsWith('http://')) {
        baseURL = new URL(params.importer)
      } else {
        baseURL = new URL(params.importer.slice(cwd.length), 'file://')
      }

      const { matched, resolvedImport } = resolveFromImportMap(params.path, importMap, baseURL)

      if (matched) {
        if (resolvedImport instanceof URL) {
          if (resolvedImport.protocol === 'file:') {
            params.path = resolvedImport.pathname
          } else {
            if (params.importer.endsWith('.css')) {
              return { path: resolvedImport.href, external: true }
            }

            return { path: `/url:${encodeURIComponent(resolvedImport.href)}`, external: true }
          }
        } else {
          result.path = resolvedImport
        }
      }
    }

    // Absolute path - append to current working dir.
    if (params.path.startsWith('/')) {
      result.path = resolve(cwd, params.path.slice(1))
    }

    const resOptions = {
      // If path is a bare module (node_modules), and resolveDir is the Proscenium runtime dir, or
      // is the current working dir, then use `cwd` as the `resolveDir`, otherwise pass it through
      // as is. This ensures that nested node_modules are resolved correctly.
      resolveDir:
        isBareModule(result.path) &&
        (!params.resolveDir.startsWith(cwd) || params.resolveDir.startsWith(runtimeDir))
          ? cwd
          : params.resolveDir,
      kind: params.kind,
      pluginData: {
        // We use this property later on, as we should ignore this resolution call.
        isResolvingPath: true
      }
    }

    // Resolve the path using esbuild's internal resolution. This allows us to import node packages
    // and extension-less paths without custom code, as esbuild with resolve them for us.
    const resolveResult = await build.resolve(result.path, resOptions)

    // Simple return the resolved result if we have an error. Usually happens when module is not
    // found.
    if (resolveResult.errors.length > 0) return resolveResult

    // If 'bundle-all' queryParam is defined, return the resolveResult.
    if (bundled || params.queryParams?.has('bundle-all')) {
      bundled = true
      return { ...resolveResult, suffix: '?bundle-all' }
    }

    // If 'bundle' queryParam is defined, return the resolveResult.
    if (params.queryParams?.has('bundle')) {
      return { ...resolveResult, suffix: '?bundle' }
    }

    if (resolveResult.path.startsWith(runtimeDir)) {
      result.path = '/proscenium-runtime' + resolveResult.path.slice(runtimeDir.length)
    } else if (!resolveResult.path.startsWith(cwd) && !isProd) {
      // Resolved path is not in the current working directory. It could be linked to a file outside
      // the CWD, or it's just invalid. If not in production, return as an outsideRoot namespaced,
      // and externally suffixed path. This lets the Rails Proscenium::Middleware::OutsideRoot
      // handle the import.
      return {
        ...resolveResult,
        namespace: 'outsideRoot',
        path: `${resolveResult.path}?outsideRoot`,
        external: true
      }
    } else {
      result.path = resolveResult.path.slice(cwd.length)
    }

    result.sideEffects = resolveResult.sideEffects

    if (
      params.path.endsWith('.css') &&
      params.kind === 'import-statement' &&
      /\.jsx?$/.test(params.importer)
    ) {
      // We're importing a CSS file from JS(X).
      return { ...resolveResult, pluginData: { importedFromJs: true } }
    } else {
      result.external = true
    }

    if (result.suffix && result.suffix !== '') {
      result.path = `${result.path}${result.suffix}`
    }

    return result
  }
})
