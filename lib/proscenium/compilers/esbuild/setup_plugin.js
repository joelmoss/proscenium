export default (pluginName, pluginFn) => {
  return (options = {}) => ({
    name: pluginName,
    async setup(build) {
      const callbacks = await pluginFn(build, options)

      callbacks.forEach(({ type, callback, filter, namespace }) => {
        if (type === 'onResolve') {
          build.onResolve({ filter, namespace }, async params => {
            if (params.pluginData?.isResolvingPath) return

            let results

            if (options.debug) {
              console.debug()
              console.group(`plugin(${pluginName}):onResolve`, { filter, namespace })
              console.debug('params:', params)

              try {
                results = await callback(params)
                console.debug('results:', results)
              } finally {
                console.groupEnd()
              }
            } else {
              results = await callback(params)
            }

            return results
          })
        } else if (type === 'onLoad') {
          build.onLoad({ filter, namespace }, async params => {
            options.debug && console.debug(`plugin(${pluginName}):onLoad`, { params })

            const results = await callback(params)

            options.debug && console.debug(`plugin(${pluginName}):onLoad`, { results })

            return results
          })
        }
      })
    }
  })
}
