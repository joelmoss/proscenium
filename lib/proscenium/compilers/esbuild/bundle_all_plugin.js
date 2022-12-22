import { dirname } from 'std/path/mod.ts'

import { loaderType, readFile, httpRegex, resolveImport } from '../../utils.js'
import setup from './setup_plugin.js'

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

        const result = await resolveImport(params, build, options.importMap)

        result.namespace = 'bundleAll'

        if (httpRegex.test(result.path)) {
          // Path is a URL, so pass the result to the url namespace.
          result.namespace = 'url'
          result.external = false
        }

        // If result is external, remove the root from the start of the path.
        if (result.external && result.path.startsWith(cwd)) {
          result.path = result.path.slice(cwd.length)
        }

        return result
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback({ path }) {
        const contents = await readFile(path)
        return { contents, resolveDir: dirname(path), loader: loaderType(path) }
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
