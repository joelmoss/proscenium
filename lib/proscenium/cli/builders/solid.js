import { build, stop } from 'esbuild'

import resolvePlugin from '../esbuild/resolve_plugin.js'
import solidjsPlugin from '../esbuild/solidjs_plugin.js'

export default async (cwd, entrypoint) => {
  const railsEnv = Deno.env.get('RAILS_ENV')
  const isProd = railsEnv === 'production'

  let entrypointIsSourcemap = false
  if (/\.jsx\.map$/.test(entrypoint)) {
    entrypoint = entrypoint.replace(/\.map$/, '')
    entrypointIsSourcemap = true
  }

  const params = {
    entryPoints: [entrypoint],
    absWorkingDir: cwd,
    logLevel: 'error',
    sourcemap: !entrypointIsSourcemap ? false : 'linked',
    outdir: 'public',
    outbase: './',
    write: false,
    format: 'esm',
    minify: isProd,
    bundle: true,
    define: {
      'process.env.NODE_ENV': `'${railsEnv}'`
    },
    plugins: [resolvePlugin({ debug: false }), solidjsPlugin({ debug: false })]
  }

  try {
    const result = await build(params)

    if (params.sourcemap === 'linked') {
      if (entrypointIsSourcemap) {
        return result.outputFiles[0].contents
      } else {
        return result.outputFiles[1].contents
      }
    } else {
      return result.outputFiles[0].contents
    }
  } finally {
    stop()
  }
}
