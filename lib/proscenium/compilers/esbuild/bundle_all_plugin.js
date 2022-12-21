import { dirname } from 'std/path/mod.ts'

import { loaderType, readFile, httpRegex, resolveImport } from '../../utils.js'
import setup from './setup_plugin.js'

export default setup('bundleAll', (build, { importMap, runtimeDir }) => {
  return [
    {
      type: 'onResolve',
      filter: /^bundle\-all:/,
      namespace: 'file',
      async callback(params) {
        params.path = params.path.slice(11)
        params.runtimeDir = runtimeDir

        const result = await resolveImport(params, build, importMap)
        result.namespace = 'bundleAll'

        return result
      }
    },

    {
      type: 'onResolve',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        params.runtimeDir = runtimeDir

        const result = await resolveImport(params, build, importMap)

        result.namespace = 'bundleAll'

        if (httpRegex.test(result.path)) {
          // Path is a URL, so pass the result to the url namespace.
          result.namespace = 'url'
          result.external = false
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
