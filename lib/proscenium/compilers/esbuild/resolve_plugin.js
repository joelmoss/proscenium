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

  return [
    {
      type: 'onResolve',
      filter: /\.rjs$/,
      callback() {
        return { external: true }
      }
    },

    {
      // Filters for imports starting with `npm:`, returning the NPM module contents.
      type: 'onResolve',
      filter: /^npm:/,
      async callback(args) {
        args.path = args.path.slice(4)

        if (args.kind === 'entry-point' && isBareModule(args.path)) {
          args.namespace = 'npm'
          args.pluginData = { isNpm: true }

          if (args.path.includes('?')) {
            const [path, query] = args.path.split('?')
            args.path = path
            args.suffix = `?${query}`
            args.queryParams = new URLSearchParams(query)
          } else if (options.cacheQueryString && options.cacheQueryString !== '') {
            args.suffix = `?${options.cacheQueryString}`
          }

          return await unbundleImport(args)
        }
      }
    },

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

    let importMapped = false
    if (importMap) {
      let baseURL
      if (params.importer.startsWith('https://') || params.importer.startsWith('http://')) {
        baseURL = new URL(params.importer)
      } else {
        baseURL = new URL(params.importer.slice(cwd.length), 'file://')
      }

      const { matched, resolvedImport } = resolveFromImportMap(params.path, importMap, baseURL)

      if (matched) {
        importMapped = true

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
      resolveDir: params.resolveDir,
      kind: params.kind,
      importer: params.importer,
      // We use this property later on, as we should ignore this resolution call.
      pluginData: { isResolvingPath: true }
    }

    // If path is matched in the import map, or is a bare module (node_modules), and resolveDir is
    // the Proscenium runtime dir, then use `cwd` as the `resolveDir`, otherwise pass it through
    // as is. This ensures that nested node_modules are resolved correctly.
    if (importMapped || (isBareModule(result.path) && params.resolveDir.startsWith(runtimeDir))) {
      resOptions.resolveDir = cwd
    } else if (!result.path.startsWith('.')) {
      // If not a relative path, ensure a real path is used, otherwise esbuild cannot resolve the
      // module.
      resOptions.resolveDir = await Deno.realPath(params.resolveDir)
    }

    // Resolve the path using esbuild's internal resolution. This allows us to import node packages
    // and extension-less paths without custom code, as esbuild will resolve them for us.
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

    // We've directly requested an NPM module, so return its content (not marked as external).
    if (params.namespace === 'npm') {
      return { ...resolveResult, pluginData: params.pluginData }
    }

    if (resolveResult.path.startsWith(runtimeDir)) {
      result.path = '/proscenium-runtime' + resolveResult.path.slice(runtimeDir.length)
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
