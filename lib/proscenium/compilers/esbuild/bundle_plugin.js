import { httpRegex, resolveImport } from '../../utils.js'
import setup from './setup_plugin.js'

export default setup('bundle', (build, options) => {
  return [
    {
      type: 'onResolve',
      filter: /^bundle:/,
      async callback(params) {
        return await bundle(params, build, options)
      }
    }
  ]
})

export async function bundle(params, build, { runtimeDir, importMap }) {
  params.path = params.path.slice(7)
  params.runtimeDir = runtimeDir

  if (httpRegex.test(params.path)) {
    // Path is a URL, so no need to resolve it. Just pass the result to the url namespace.
    return { path: params.path, external: false, namespace: 'url' }
  }

  const result = await resolveImport(params, build, importMap)

  if (httpRegex.test(result.path)) {
    // Path is a URL, so pass the result to the url namespace.
    result.namespace = 'url'
    result.external = false
  }

  return result
}
