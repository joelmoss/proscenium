import setup from './setup_plugin.js'
import { isBareModule, resolveImport } from '../../utils.js'

/**
 Handles npm: prefixed entrypoints, returning the contents of the requested locally installed NPM
 module. Note that this will ignore any import map.
 */
export default setup('npm', (build, options) => {
  return [
    {
      type: 'onResolve',
      filter: /^npm:/,
      async callback(params) {
        const origPath = params.path
        params.path = params.path.slice(4)

        // params.pluginData ??= {}
        // params.pluginData.prefix = 'npm'
        // params.namespace = 'npm'

        if (params.kind === 'entry-point' && isBareModule(params.path)) {
          if (params.path.includes('?')) {
            const [path, query] = params.path.split('?')
            params.path = path
            params.suffix = `?${query}`
            params.queryParams = new URLSearchParams(query)
          } else if (options.cacheQueryString && options.cacheQueryString !== '') {
            params.suffix = `?${options.cacheQueryString}`
          }

          const result = await resolveImport(params, build)
          result.pluginData = { entryPoint: origPath }
          return result
        }
      }
    }

    // {
    //   type: 'onResolve',
    //   filter: /.*/,
    //   namespace: 'npm',
    //   // Handle imports within npm namespace.
    //   async callback(params) {
    //     return { path: params.path }
    //   }
    // },
    // {
    //   type: 'onLoad',
    //   filter: /.*/,
    //   namespace: 'npm',
    //   async callback(params) {
    //     const contents = await readFile(params.path)
    //     return { contents, resolveDir: dirname(params.path), loader: loaderType(params.path) }
    //   }
    // },
  ]
})
