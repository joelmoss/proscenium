import { resolve } from 'std/path/mod.ts'

import { setup } from '../utils.js'

const importKinds = ['import-statement', 'dynamic-import', 'require-call']

export default setup('resolve', build => {
  const cwd = build.initialOptions.absWorkingDir

  return {
    onResolve: {
      filter: /.*/,
      async callback(args) {
        // Remote modules
        if (args.path.startsWith('http://') || args.path.startsWith('https://')) {
          return { external: true }
        }

        // Proscenium runtime
        if (args.path.startsWith('/proscenium-runtime')) {
          return { external: true }
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
    const result = { path: params.path }

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
      // report errors?
      // throw `${resolveResult.errors[0].text} (resolveDir: ${cwd})`
    }

    result.path = resolveResult.path.slice(cwd.length)
    result.sideEffects = resolveResult.sideEffects

    if (
      params.path.endsWith('.css') &&
      params.kind === 'import-statement' &&
      /\.jsx?$/.test(params.importer)
    ) {
      // We're importing a CSS file from JS(X).
      result.namespace = 'importStylesheet'
    } else {
      // Requested path is a bare module.
      result.external = true
    }

    return result
  }
})

function isBareModule(path) {
  return !path.startsWith('.') && !path.startsWith('/')
}