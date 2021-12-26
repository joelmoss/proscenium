import * as esbuild from 'https://deno.land/x/esbuild@v0.14.8/mod.js'

import debugPlugin from './esbuild/debug_plugin.js'
import resolvePlugin from './esbuild/resolve_plugin.js'

export default async (cwd, entrypoint, options = {}) => {
  if (!cwd || !entrypoint) {
    throw new TypeError('`cwd` and `entrypoint` arguments are required')
  }

  try {
    return await esbuild.build({
      entryPoints: [entrypoint],
      absWorkingDir: cwd,
      logLevel: 'silent',
      write: false,
      format: 'esm',
      bundle: true,
      plugins: [options.debug && debugPlugin, resolvePlugin].filter(Boolean)
    })
  } finally {
    esbuild.stop()
  }
}
