import { join } from 'std/path/mod.ts'

import CliArgumentError from './argument_error.js'
import { builderNames } from './builders/index.js'

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
          if (params.pluginData?.isResolvingPath) return

          const results = await callback(params)

          options.debug && console.debug(`plugin(${pluginName}:onResolve)`, { params, results })

          return results
        })
      }

      if (plugin.onLoad) {
        const { callback, ...onLoad } = plugin.onLoad

        build.onLoad(onLoad, params => {
          const results = callback(params)

          options.debug && console.debug(`plugin(${pluginName}:onLoad)`, { params, results })

          return results
        })
      }
    }
  })
}

export const parseArgs = args => {
  let [cwd, entrypoint, builder] = args

  if (!cwd) {
    throw new CliArgumentError('cwdRequired')
  }

  if (!entrypoint) {
    throw new CliArgumentError('entrypointRequired')
  }

  if (!builder) {
    throw new CliArgumentError('builderRequired')
  }

  try {
    const stat = Deno.lstatSync(cwd)
    if (!stat.isDirectory) {
      throw new CliArgumentError(
        `Current working directory is required as the first argument - received ${cwd}`
      )
    }
  } catch {
    throw new CliArgumentError('cwdUnknown', { cwd })
  }

  if (/\.(jsx?)|(css)\.map$/.test(entrypoint)) {
    entrypoint = entrypoint.replace(/\.map$/, '')
  }

  try {
    const stat = Deno.lstatSync(join(cwd, entrypoint))
    if (!stat.isFile) {
      throw new CliArgumentError(
        `Entrypoint is required as the second argument - received ${entrypoint}`
      )
    }
  } catch {
    throw new CliArgumentError('entrypointUnknown', { entrypoint })
  }

  if (!builderNames.includes(builder)) {
    throw new CliArgumentError('builderUnknown', { builder })
  }

  return args
}
