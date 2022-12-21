import { dirname } from 'std/path/mod.ts'

import { readFile, httpRegex, resolveImport } from '../../utils.js'
import setup from './setup_plugin.js'

export default setup('bundleAll', build => {
  return [
    {
      type: 'onResolve',
      filter: /^bundle\-all:/,
      namespace: 'file',
      async callback(params) {
        params.path = params.path.slice(11)

        const result = await resolveImport(params, build)
        result.namespace = 'bundleAll'

        return result
      }
    },

    {
      type: 'onResolve',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        const result = await resolveImport(params, build)

        result.namespace = 'bundleAll'

        if (httpRegex.test(result.path)) {
          // Path is a URL, so pass the result to the url namespace.
          result.namespace = 'url'
        }

        return result
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'bundleAll',
      async callback(params) {
        const contents = await readFile(params.path)
        return { contents, resolveDir: dirname(params.path) }
      }
    }
  ]
})
