import { dirname } from 'std/path/mod.ts'

import setup from './setup_plugin.js'
import { readFile, isBareModule, loaderType } from '../../utils.js'

/**
 Renders an SVG React component when imported from JSX.
 */
export default setup('npm', (build, options) => {
  const cwd = build.initialOptions.absWorkingDir

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

          return { path: params.path, namespace: 'npm' }
          // return await resolve(params)
        }
      }
    },

    {
      type: 'onLoad',
      filter: /.*/,
      namespace: 'npm',
      async callback(params) {
        const contents = await readFile(params.path)
        return { contents, resolveDir: dirname(params.path), loader: loaderType(params.path) }
      }
    }
  ]
})
