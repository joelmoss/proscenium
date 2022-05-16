import { build, stop } from 'esbuild'

import resolvePlugin from '../esbuild/resolve_plugin.js'

export default async (cwd, entrypoint) => {
  const railsEnv = Deno.env.get('RAILS_ENV')
  const isProd = railsEnv === 'production'

  let entrypointIsSourcemap = false
  if (/\.jsx?\.map$/.test(entrypoint)) {
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
    jsxFactory: 'createElement',
    jsxFragment: 'Fragment',
    minify: isProd,
    bundle: true,
    banner: { js: [] },
    define: {
      'process.env.NODE_ENV': `'${railsEnv}'`
    },
    plugins: [resolvePlugin({ debug: false })]
  }

  if (entrypoint.endsWith('.jsx')) {
    params.banner.js.push(`import { createElement, Fragment } from "react";`)
  }

  params.banner.js = params.banner.js.join('\n')

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
