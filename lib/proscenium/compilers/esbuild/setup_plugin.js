export default (pluginName, pluginFn) => {
  return (options = {}) => ({
    name: pluginName,
    async setup(build) {
      const callbacks = await pluginFn(build, options)

      callbacks.forEach(({ type, callback, filter, namespace }) => {
        if (type === 'onResolve') {
          build.onResolve({ filter, namespace }, async params => {
            if (params.pluginData?.isResolvingPath) return

            options.debug &&
              console.debug(`plugin(${pluginName}):onResolve`, params.path, { params })

            const results = await callback(params)

            options.debug &&
              console.debug(`plugin(${pluginName}):onResolve`, params.path, { results })

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
