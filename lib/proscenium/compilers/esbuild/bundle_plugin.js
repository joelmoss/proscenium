import { httpRegex, resolveImport } from '../../utils.js'
import setup from './setup_plugin.js'

export default setup('bundle', (build, { importMap }) => {
  return [
    {
      type: 'onResolve',
      filter: /^bundle:/,
      async callback(params) {
        params.path = params.path.slice(7)

        const result = await resolveImport(params, build, importMap)

        if (httpRegex.test(result.path)) {
          // Path is a URL, so pass the result to the url namespace.
          result.namespace = 'url'
          result.external = false
        }

        return result
      }
    }
  ]
})
