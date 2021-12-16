import * as esbuild from 'https://deno.land/x/esbuild@v0.14.5/mod.js'

const debugPlugin = {
  name: 'debug',
  setup(build) {
    build.onResolve({ filter: /.*/ }, args => {
      console.log('onResolve', args)
    })
    build.onLoad({ filter: /.*/ }, args => {
      console.log('onLoad', args)
    })
  }
}

export default async (cwd, entrypoint) => {
  if (!cwd || !entrypoint) {
    throw new TypeError('`cwd` and `entrypoint` arguments are required')
  }

  try {
    return await esbuild.build({
      entryPoints: [entrypoint],
      absWorkingDir: cwd,
      logLevel: 'silent',
      write: false,
      format: 'esm'
      // plugins: [debugPlugin],
    })
  } finally {
    esbuild.stop()
  }
}
