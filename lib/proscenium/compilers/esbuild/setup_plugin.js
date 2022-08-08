export default (pluginName, pluginFn) => {
  return (options = {}) => ({
    name: pluginName,
    async setup(build) {
      const plugin = await pluginFn(build, options)

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

        build.onLoad(onLoad, async params => {
          options.debug && console.debug(`plugin(${pluginName}):onLoad`, { params })
          const results = await callback(params)
          options.debug && console.debug(`plugin(${pluginName}):onLoad`, { results })

          return results
        })
      }
    }
  })
}
