import { resolve } from 'std/path/mod.ts'

import { setup } from '../utils.js'

const importKinds = ['import-statement', 'dynamic-import', 'require-call']

export default setup('resolve', build => {
  const cwd = build.initialOptions.absWorkingDir

  return {
    onResolve: {
      filter: /.*/,
      async callback(args) {
        // Package is a CSS file that is being imported from JS, so delegate this to the
        // importStylesheet namespace.
        // if (args.path === 'importStylesheet') {
        //   return {
        //     path: 'importStylesheet',
        //     namespace: 'importStylesheet'
        //   }
        // }

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
        return {
          contents: `
          import adoptCssModules from '/proscenium-runtime/adopt_css_module.js'
          export default await adoptCssModules('${args.path}')
          `,
          resolveDir: cwd,
          loader: 'js'
        }
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

    // Handle importing of react from react_shim runtime package.
    if (params.resolveDir.endsWith('proscenium/runtime/react_shim') && result.path === 'react') {
      params.resolveDir = cwd
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
      // TODO: log and report errors somehow, as it may not be as simple as an unknown module
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
      // } else if (!isBareModule(params.path)) {
      //   return resolveResult
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
