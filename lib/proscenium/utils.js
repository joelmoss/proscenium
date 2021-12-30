export const isTest = () => Deno.env.get('ENVIRONMENT') === 'test'

export const debug = (...args) => {
  isTest() && console.log(...args)
}

export const setup = (pluginName, pluginFn) => {
  return (options = {}) => ({
    name: pluginName,
    setup(build) {
      const plugin = pluginFn(build)

      if (plugin.onResolve) {
        const { callback, ...onResolve } = plugin.onResolve

        build.onResolve(onResolve, async params => {
          const results = await callback(params)

          options.debug &&
            results &&
            console.debug(`plugin(${pluginName}:onResolve)`, { params, results })

          return results
        })
      }

      if (plugin.onLoad) {
        const { callback, ...onLoad } = plugin.onLoad

        build.onLoad(onLoad, params => {
          const results = callback(params)

          options.debug &&
            results &&
            console.debug(`plugin(${pluginName}:onLoad)`, { params, results })

          return results
        })
      }
    }
  })
}
