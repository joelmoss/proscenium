import setup from './setup_plugin.js'
import { resolvePath } from './import_map/resolver.js'

const httpRegex = /^https?:\/\//

/**
 Resolves import map if it exists.
 */
export default setup('importMap', (build, options) => {
  const { importMap } = options
  const cwd = build.initialOptions.absWorkingDir

  return [
    {
      type: 'onResolve',
      filter: /.*/,
      callback({ kind, importer, path }) {
        if (!importMap || kind === 'entry-point') return

        let baseURL
        if (httpRegex.test(importer)) {
          baseURL = new URL(importer)
        } else {
          baseURL = new URL(importer.slice(cwd.length), 'file://')
        }

        const { matched, resolvedImport } = resolvePath(path, importMap, baseURL)

        if (matched) {
          let path
          const external = true

          if (resolvedImport instanceof URL) {
            if (resolvedImport.protocol === 'file:') {
              path = resolvedImport.pathname
            } else {
              path = `/url:${encodeURIComponent(resolvedImport.href)}`
            }
          } else {
            path = resolvedImport
          }

          return { path, external }
        }
      }
    }
  ]
})
