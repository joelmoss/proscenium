import { dirname } from 'std/path/mod.ts'

import { readFile } from '../../utils.js'

export default options => {
  const { debug } = options

  return {
    name: 'bundleAll',
    setup(build) {
      build.onResolve({ filter: /^bundle\-all:/, namespace: 'file' }, async params => {
        const result = await build.resolve(params.path.slice(10), {
          resolveDir: params.resolveDir,
          importer: params.importer,
          pluginData: { isResolvingPath: true }
        })

        result.namespace = 'bundleAll'

        debug && console.log('bundleAll(onResolve#1)', { params, result })

        return result
      })

      build.onResolve({ filter: /.*/, namespace: 'bundleAll' }, async params => {
        const result = await build.resolve(params.path, {
          resolveDir: params.resolveDir,
          importer: params.importer,
          pluginData: { isResolvingPath: true }
        })

        result.namespace = 'bundleAll'

        debug && console.log('bundleAll(onResolve#2)', { params, result })

        return result
      })

      build.onLoad({ filter: /.*/, namespace: 'bundleAll' }, async params => {
        const contents = await readFile(params.path)
        const result = { contents, resolveDir: dirname(params.path) }

        debug && console.log('bundleAll(onLoad)', { params, result })

        return result
      })
    }
  }
}
