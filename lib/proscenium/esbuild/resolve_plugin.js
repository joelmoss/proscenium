import { resolve } from 'https://deno.land/std@0.119.0/path/mod.ts'

export default {
  name: 'resolve',
  setup(build) {
    const cwd = build.initialOptions.absWorkingDir

    // Handle local imports by modifying the returned path to be an absolute path that is relative
    // to the current working directory.
    build.onResolve({ filter: /^[^http].+$/ }, async args => {
      if (args.kind === 'import-statement') {
        return await unbundleImport(args)
      }
    })

    async function unbundleImport(params) {
      params = await resolveImport(params)

      return {
        path: params.path.slice(cwd.length),
        external: true
      }
    }

    // Resolve the given `params.path` to an absolute path.
    async function resolveImport(params) {
      if (params.path.startsWith('http')) {
        params.resolvedAs = 'url'
      }

      // Absolute path - append to current working dir.
      else if (params.path.startsWith('/')) {
        params.resolvedAs = 'absolute'
        params.path = resolve(cwd, params.path.slice(1))
      }

      // Relative path - append to params.resolveDir.
      else if (params.path.startsWith('.')) {
        params.resolvedAs = 'relative'
        params.path = resolve(params.resolveDir, params.path)
      }

      // Bare module.
      else {
        if (!params.pluginData?.resolve) {
          const result = await build.resolve(params.path, {
            resolveDir: cwd,
            pluginData: {
              resolve: true
            }
          })

          params.resolvedAs = 'bare'
          params.path = result.path
          params.sideEffects = result.sideEffects
        }
      }

      return params
    }
  }
}
