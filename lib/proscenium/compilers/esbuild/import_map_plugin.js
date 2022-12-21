import setup from './setup_plugin.js'
import { bundle } from './bundle_plugin.js'
import { bundleAll } from './bundle_all_plugin.js'
import { resolveWithImportMap } from '../../utils.js'

/**
 Resolves `bundle` and `bundle-all` prefixed paths with import map. Everything else is passed
 through as is.
 */
export default setup('importMap', (build, options) => {
  const cwd = build.initialOptions.absWorkingDir

  return [
    {
      type: 'onResolve',
      filter: /.*/,
      async callback(params) {
        if (!options.importMap || params.kind === 'entry-point') return

        const mappedPath = resolveWithImportMap(options.importMap, params, cwd)
        if (mappedPath) {
          if (mappedPath.startsWith('bundle:')) {
            delete options.importMap // do not parse import map again

            return await bundle({ ...params, path: mappedPath }, build, options)
          } else if (mappedPath.startsWith('bundle-all:')) {
            delete options.importMap // do not parse import map again

            return await bundleAll({ ...params, path: mappedPath }, build, options)
          }
        }
      }
    }
  ]
})
