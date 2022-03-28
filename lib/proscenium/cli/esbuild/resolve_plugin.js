import { resolve } from 'https://deno.land/std@0.119.0/path/mod.ts'

import { setup } from '../utils.js'

export default setup('resolve', build => {
  const cwd = build.initialOptions.absWorkingDir

  return {
    onResolve: {
      filter: /^[^https?].+$/,
      async callback(args) {
        // Package is a CSS file that is being imported from JS, so delegate this to the
        // importStylesheet namespace.
        // if (args.path === 'importStylesheet') {
        //   return {
        //     path: 'importStylesheet',
        //     namespace: 'importStylesheet'
        //   }
        // }

        if (args.path.startsWith('/proscenium-runtime')) {
          return { external: true }
        }

        // Import statements are unbundled here.
        if (args.kind === 'import-statement' || args.kind === 'dynamic-import') {
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
      return { errors: resolveResult.errors }
    }

    result.path = resolveResult.path.slice(cwd.length)
    result.sideEffects = resolveResult.sideEffects

    // If importing a CSS file from JS(X), set the namespace to 'appendStylesheet', otherwise mark
    // as external.
    if (
      params.path.endsWith('.css') &&
      params.kind === 'import-statement' &&
      /\.jsx?$/.test(params.importer)
    ) {
      result.namespace = 'importStylesheet'
    } else {
      result.external = true
    }

    return result
  }
})
