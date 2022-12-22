import setup from './setup_plugin.js'
import { bundle } from './bundle_plugin.js'
import { bundleAll } from './bundle_all_plugin.js'
import { resolveWithImportMap } from '../../utils.js'

/**
 Resolves `bundle` and `bundle-all` prefixed paths with import map. Everything else is passed
 through as is. Note that if a match is found in the import map with a prefix (bundle, bundle-all),
 the import map will not be used again in the returned path.
 */
export default setup('importMap', (build, { importMap, runtimeDir }) => {
  const cwd = build.initialOptions.absWorkingDir

  return [
    {
      type: 'onResolve',
      filter: /.*/,
      async callback(params) {
        if (!importMap || params.kind === 'entry-point') return

        const mappedPath = resolveWithImportMap(importMap, params, cwd)
        if (mappedPath) {
          if (mappedPath.startsWith('bundle:')) {
            return await bundle({ ...params, path: mappedPath }, build, { runtimeDir })
          } else if (mappedPath.startsWith('bundle-all:')) {
            return await bundleAll({ ...params, path: mappedPath }, build, { runtimeDir })
          }
        }
      }
    }
  ]
})
