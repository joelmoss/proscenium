import * as esbuild from 'https://deno.land/x/esbuild@v0.14.8/mod.js'

import resolvePlugin from './esbuild/resolve_plugin.js'
import cssPlugin, { appendStylesheetPlugin } from './esbuild/css_plugin.js'

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
      plugins: applyOptions(options, [resolvePlugin]).filter(Boolean)
    })
  } finally {
    esbuild.stop()
  }
}

function applyOptions(options, plugins) {
  return plugins.map(plugin => (typeof plugin === 'function' ? plugin(options) : plugin))
}
