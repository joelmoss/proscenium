import { build, stop } from 'esbuild'

const isProd = Deno.env.get('RAILS_ENV') === 'production'
const isTest = Deno.env.get('RAILS_ENV') === 'test'

export default async (cwd, entrypoint) => {
  const params = {
    entryPoints: [entrypoint],
    absWorkingDir: cwd,
    logLevel: 'error',
    sourcemap: isTest ? false : 'inline',
    write: false,
    format: 'esm',
    jsxFactory: 'createElement',
    jsxFragment: 'Fragment',
    inject: ['./lib/react_shim.js'],
    minify: isProd,
    bundle: true
    // plugins: [resolvePlugin({ debug })]
  }

  try {
    const result = await build(params)
    return result.outputFiles[0].contents
  } finally {
    stop()
  }
}
