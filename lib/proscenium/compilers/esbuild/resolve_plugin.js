import { join, resolve } from 'std/path/mod.ts'
import {
  parseFromString as parseImportMap,
  resolve as resolveFromImportMap
} from 'import-maps/resolve'

import setup from './setup_plugin.js'

const baseURL = new URL('file://')
const importKinds = ['import-statement', 'dynamic-import', 'require-call']

export default setup('resolve', (build, options) => {
  const { runtimeDir } = options
  const cwd = build.initialOptions.absWorkingDir
  const runtimeCwdAlias = `${cwd}/proscenium-runtime`
  const importMap = readImportMap()

  return {
    onResolve: {
      filter: /.*/,
      async callback(args) {
        if (args.path.includes('?')) {
          const [path, query] = args.path.split('?')
          args.path = path
          args.suffix = `?${query}`
          args.queryParams = new URLSearchParams(query)
        }

        // Mark remote modules as external.
        //
        // TODO: support bundling of remotes.
        if (args.path.startsWith('http://') || args.path.startsWith('https://')) {
          return { external: true }
        }

        // Proscenium runtime
        if (args.path.startsWith('@proscenium/')) {
          const result = { suffix: args.suffix }

          if (args.queryParams?.has('bundle')) {
            result.path = join(runtimeDir, `${args.path.replace(/^@proscenium/, '')}/index.js`)
          } else {
            result.path = `${args.path.replace(/^@proscenium/, '/proscenium-runtime')}/index.js`
            result.external = true
          }

          return result
        }

        if (args.path.startsWith(runtimeCwdAlias)) {
          return { path: join(runtimeDir, args.path.slice(runtimeCwdAlias.length)) }
        }

        // Everything else is unbundled.
        if (importKinds.includes(args.kind)) {
          return await unbundleImport(args)
        }
      }
    },

    onLoad: {
      filter: /.*/,
      namespace: 'importStylesheet',
      callback(args) {
        const result = {
          resolveDir: cwd,
          loader: 'js'
        }

        if (args.path.endsWith('.module.css')) {
          result.contents = `
              import { importCssModule } from '/proscenium-runtime/import_css.js'
              export default await importCssModule('${args.path}')
            `
        } else {
          result.contents = `
            import { appendStylesheet } from '/proscenium-runtime/import_css.js'
            appendStylesheet('${args.path}')
          `
        }

        return result
      }
    }
  }

  // Resolve the given `params.path` to a path relative to the Rails root.
  //
  // Examples:
  //  'react' -> '/.../node_modules/react/index.js'
  //  './my_module' -> '/.../app/my_module.js'
  //  '/app/my_module' -> '/.../app/my_module.js'
  async function unbundleImport(params) {
    const result = { path: params.path, suffix: params.suffix }

    if (importMap) {
      const { matched, resolvedImport } = resolveFromImportMap(params.path, importMap, baseURL)
      if (matched) {
        if (resolvedImport.protocol === 'file:') {
          params.path = resolvedImport.pathname
        } else {
          return { path: resolvedImport.href, external: true }
        }
      }
    }

    // Absolute path - append to current working dir.
    if (params.path.startsWith('/')) {
      result.path = resolve(cwd, params.path.slice(1))
    }

    // Resolve the path using esbuild's internal resolution. This allows us to import node packages
    // and extension-less paths without custom code, as esbuild with resolve them for us.
    const resolveResult = await build.resolve(result.path, {
      resolveDir: params.resolveDir,
      pluginData: {
        // We use this property later on, as we should ignore this resolution call.
        isResolvingPath: true
      }
    })

    if (resolveResult.errors.length > 0) {
      // throw `${resolveResult.errors[0].text} (resolveDir: ${cwd})`
    }

    // If bundle queryParam is defined, return the resolveResult.
    if (params.queryParams?.has('bundle')) {
      return { ...resolveResult, suffix: result.suffix }
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
      result.namespace = 'importStylesheet'
    } else {
      result.external = true
    }

    return result
  }

  function readImportMap() {
    const file = join(cwd, 'config', 'import_map.json')
    let source

    try {
      source = Deno.readTextFileSync(file)
    } catch {
      return null
    }

    return parseImportMap(source, baseURL)
  }
})

function isBareModule(path) {
  return !path.startsWith('.') && !path.startsWith('/')
}
