import setup from './setup_plugin.js'
import { resolveImport } from '../../utils.js'

/**
 Handles `gem:` prefixed entrypoints.
 */
export default setup('gem', (build, options) => {
  return [
    {
      type: 'onResolve',
      filter: /^gem:/,
      async callback(params) {
        const origPath = params.path
        params.path = params.path.slice(4)

        if (params.kind === 'entry-point') {
          if (params.path.includes('?')) {
            const [path, query] = params.path.split('?')
            params.path = path
            params.suffix = `?${query}`
            params.queryParams = new URLSearchParams(query)
          } else if (options.cacheQueryString && options.cacheQueryString !== '') {
            params.suffix = `?${options.cacheQueryString}`
          }

          const gemName = params.path.split('/')[0]
          params.path = params.path.slice(gemName.length)

          const result = await resolveImport(params, build)
          result.pluginData = { entryPoint: origPath, gemName }
          return result
        }
      }
    }
  ]
})
