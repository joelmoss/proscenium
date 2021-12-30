import { resolve } from 'https://deno.land/std@0.119.0/path/mod.ts'

import { setup } from '../utils.js'

export default setup('resolve', build => {
  const cwd = build.initialOptions.absWorkingDir

  return {
    onResolve: {
      filter: /^[^https?].+$/,
      async callback(args) {
        if (args.path === 'appendStylesheet') {
          return {
            path: 'appendStylesheet',
            namespace: 'appendStylesheet'
          }
        } else if (args.kind === 'import-statement') {
          return await unbundleImport(args)
        }
      }
    },

    onLoad: {
      filter: /.*/,
      namespace: 'appendStylesheet',
      callback(args) {
        if (args.path === 'appendStylesheet') {
          return {
            contents: `
              export default function(path) {
                const ele = document.createElement('link')
                ele.setAttribute('rel', 'stylesheet')
                ele.setAttribute('media', 'all')
                ele.setAttribute('href', path)
                document.head.appendChild(ele)
              }
            `,
            loader: 'js'
          }
        }

        return {
          contents: `
            import appendStylesheet from 'appendStylesheet';
            appendStylesheet("${args.path}")
          `,
          loader: 'js'
        }
      }
    }
  }

  async function unbundleImport(params) {
    const result = await resolveImport(params)

    const cssImportedFromJs =
      params.path.endsWith('.css') &&
      params.kind === 'import-statement' &&
      params.importer.endsWith('js')

    return {
      path: result.path.slice(cwd.length),
      external: !cssImportedFromJs,
      namespace: cssImportedFromJs ? 'appendStylesheet' : undefined
    }
  }

  // Resolve the given `params.path` to the Rails root.
  //
  // Examples:
  //  'react' -> '/node_modules/react/index.js'
  //  './my_module' -> '/app/my_module.js'
  //  '/app/my_module' -> '/app/my_module.js'
  async function resolveImport(params) {
    const result = {}

    // Absolute path - append to current working dir.
    if (params.path.startsWith('/')) {
      result.pluginData = { resolvedAs: 'absolute' }
      result.path = resolve(cwd, params.path.slice(1))
    }

    // Relative path - append to params.resolveDir.
    else if (params.path.startsWith('.')) {
      result.pluginData = { resolvedAs: 'relative' }
      result.path = resolve(params.resolveDir, params.path)
    }

    // Bare module.
    else {
      // Only attempt module resolution if the request is not an internal resolution.
      if (!params.pluginData?.isInternalResolution) {
        const resolveResult = await build.resolve(params.path, {
          resolveDir: cwd,
          pluginData: {
            // This is an internal resolution, so we don't want to recurse.
            isInternalResolution: true
          }
        })

        result.pluginData = { resolvedAs: 'bare' }
        result.path = resolveResult.path
        result.sideEffects = resolveResult.sideEffects
      }
    }

    return result
  }
})
