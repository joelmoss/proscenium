export default (pluginName, pluginFn) => {
  return (options = {}) => ({
    name: pluginName,
    setup(build) {
      const plugin = pluginFn(build, options)

      if (plugin.onResolve) {
        const { callback, ...onResolve } = plugin.onResolve

        build.onResolve(onResolve, async params => {
          if (params.pluginData?.isResolvingPath) return

          options.debug && console.debug(`plugin(${pluginName}):onResolve`, params.path, { params })
          const results = await callback(params)
          options.debug &&
            console.debug(`plugin(${pluginName}):onResolve`, params.path, { results })

          return results
        })
      }

      if (plugin.onLoad) {
        const { callback, ...onLoad } = plugin.onLoad

        build.onLoad(onLoad, params => {
          options.debug && console.debug(`plugin(${pluginName}):onLoad`, { params })
          const results = callback(params)
          options.debug && console.debug(`plugin(${pluginName}):onLoad`, { results })

          return results
        })
      }
    }
  })
}
