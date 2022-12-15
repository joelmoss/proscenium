import { join, dirname, resolve as resolvePath } from 'std/path/mod.ts'
import resolveFromImportMap from './import_map/resolver.js'
import { cache } from 'cache'

import setup from './setup_plugin.js'
import { isBareModule, loaderType } from '../../utils.js'

const importKinds = ['import-statement', 'dynamic-import', 'require-call', 'import-rule']
const httpRegex = /^https?:\/\//

export default setup('resolve', (build, options) => {
  const { runtimeDir, importMap } = options
  const cwd = build.initialOptions.absWorkingDir
  const runtimeCwdAlias = `${cwd}/proscenium-runtime`

  return [
    {
      type: 'onResolve',
      filter: /^bundle\-all:/,
      namespace: 'file',
      async callback(params) {
        // return { path: `/proscenium/${params.path}`, external: true }

        if (importKinds.includes(params.kind)) {
          params.path = params.path.slice(11)
          const result = await resolve(params, false)

          result.pluginData = { bundleAll: true }
          result.namespace = 'bundleAll'

          return result
        }
      }
    },
    {
      type: 'onResolve',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        if (importKinds.includes(params.kind)) {
          const result = await resolve(params, false)
          result.namespace = 'bundleAll'

          if (httpRegex.test(result.path)) {
            // Path is a URL, so pass the result to the url namespace.
            result.namespace = 'url'
          }

          return result
        }
      }
    },
    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        const contents = await Deno.readTextFile(params.path)
        return { contents, resolveDir: dirname(params.path), loader: loaderType(params.path) }
      }
    },

    {
      type: 'onResolve',
      filter: /^bundle:/,
      async callback(params) {
        if (importKinds.includes(params.kind)) {
          params.path = params.path.slice(7)

          const result = await resolve(params, false)

          if (httpRegex.test(result.path)) {
            // Path is a URL, so pass the result to the url namespace.
            result.namespace = 'url'
          }

          return result
        }
      }
    },

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

          return await resolve(args)
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

        return { contents, loader: loaderType(args.path) }
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

        // Rewrite the path to the actual runtime directory.
        if (args.path.startsWith(runtimeCwdAlias)) {
          return { path: join(runtimeDir, args.path.slice(runtimeCwdAlias.length)) }
        }

        // Everything else is unbundled.
        if (importKinds.includes(args.kind)) {
          return await resolve(args)
        }
      }
    }
  ]

  async function resolve(params, external = true) {
    // Externalise URL's with a `url:` prefix, which is then handled by the Url Middleware.
    if (httpRegex.test(params.path)) {
      return { path: external ? `/url:${encodeURIComponent(params.path)}` : params.path, external }
    }

    let result = resolveFromImportMap(importMap, cwd, params, external)

    let importMapped = false
    if (result) {
      // Import map has marked this path as external, so return it now.
      if (result.external) return result

      importMapped = true
    } else {
      result = { path: params.path, suffix: params.suffix }
    }

    if (result.path.endsWith('.rjs')) {
      return { external: true, path: result.path }
    }

    // Absolute path - append to current working dir.
    if (result.path.startsWith('/')) {
      result.path = resolvePath(cwd, result.path.slice(1))
    }

    const resOptions = {
      resolveDir: params.resolveDir,
      kind: params.kind,
      importer: params.importer,
      pluginData: {
        ...params.pluginData,

        // We use this property later on, as we should ignore this resolution call.
        isResolvingPath: true
      }
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
    result = await build.resolve(result.path, resOptions)

    if (result.errors.length > 0) return result

    // We've directly requested an NPM module, so return its content (not marked as external).
    if (params.namespace === 'npm') {
      return { ...result, pluginData: params.pluginData }
    }

    if (
      result.path.endsWith('.css') &&
      params.kind === 'import-statement' &&
      /\.jsx?$/.test(params.importer)
    ) {
      // We're importing a CSS file from JS(X).
      return { ...result, pluginData: { importedFromJs: true } }
    }

    delete result.namespace

    result.external = external

    if (result.external) {
      // Path is now external, so make sure it is an absolute URL path.
      result.path = result.path.slice(cwd.length)

      if (params.suffix && params.suffix !== '') {
        result.path = `${result.path}${params.suffix}`
      }
    }

    return result
  }
})
