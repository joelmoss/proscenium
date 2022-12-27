import { dirname } from 'std/path/mod.ts'

import { loaderType, readFile, httpRegex, resolveImport } from '../../utils.js'
import setup from './setup_plugin.js'
import { onLoad as onCssLoad } from './css_plugin.js'

export default setup('bundleAll', (build, options) => {
  const cwd = build.initialOptions.absWorkingDir

  return [
    {
      type: 'onResolve',
      filter: /^bundle\-all:/,
      namespace: 'file',
      async callback(params) {
        return await bundleAll(params, build, options)
      }
    },

    {
      type: 'onResolve',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        params.runtimeDir = options.runtimeDir

        // Strip "bundle:" and "bundle-all:" prefixes, as we're bundling all anyway.
        if (params.path.startsWith('bundle:')) {
          params.path = params.path.slice(7)
        } else if (params.path.startsWith('bundle-all:')) {
          params.path = params.path.slice(11)
        }

        if (httpRegex.test(params.path)) {
          // Path is a URL, so no need to resolve it. Just pass the result to the url namespace.
          return { path: params.path, external: false, namespace: 'url' }
        }

        const result = await resolveImport(params, build, options.importMap)

        result.namespace = 'bundleAll'

        if (httpRegex.test(result.path)) {
          // Path is a URL, so pass the result to the url namespace.
          result.namespace = 'url'
          result.external = false
        } else if (result.external && result.path.startsWith(cwd)) {
          // If result is external, remove the root from the start of the path.
          result.path = result.path.slice(cwd.length)
        }

        return result
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        if (params.path.endsWith('.css')) {
          const result = await onCssLoad(params, { cwd, ...options })
          return { ...result, resolveDir: dirname(params.path) }
        } else {
          const contents = await readFile(params.path)
          return { contents, resolveDir: dirname(params.path), loader: loaderType(params.path) }
        }
      }
    }
  ]
})

export async function bundleAll(params, build, { importMap, runtimeDir }) {
  params.path = params.path.slice(11)
  params.runtimeDir = runtimeDir

  const result = await resolveImport(params, build, importMap)
  result.namespace = 'bundleAll'

  return result
}
