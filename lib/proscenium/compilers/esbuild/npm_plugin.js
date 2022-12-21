import setup from './setup_plugin.js'
import { isBareModule, resolveImport } from '../../utils.js'

/**
 Handles npm: prefixed paths, returning the contents of the requested locally installed NPM module.
 */
export default setup('npm', (build, options) => {
  return [
    {
      // Filters for entry points starting with `npm:`, and returns the matching NPM module.
      type: 'onResolve',
      filter: /^npm:/,
      async callback(params) {
        params.path = params.path.slice(4)
        params.pluginData ??= {}
        params.pluginData.prefix = 'npm'
        params.namespace = 'npm'

        if (params.kind === 'entry-point' && isBareModule(params.path)) {
          if (params.path.includes('?')) {
            const [path, query] = params.path.split('?')
            params.path = path
            params.suffix = `?${query}`
            params.queryParams = new URLSearchParams(query)
          } else if (options.cacheQueryString && options.cacheQueryString !== '') {
            params.suffix = `?${options.cacheQueryString}`
          }

          return await resolveImport(params, build)
        }
      }
    }
  ]
})
