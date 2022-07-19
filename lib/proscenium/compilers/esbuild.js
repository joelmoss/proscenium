import { writeAll } from 'std/streams/mod.ts'
import { parse as parseArgs } from 'std/flags/mod.ts'
import { expandGlob } from 'std/fs/mod.ts'
import { join, isGlob, resolve, dirname, fromFileUrl } from 'std/path/mod.ts'
import { build, stop } from 'esbuild'

import envPlugin from './esbuild/env_plugin.js'
import resolvePlugin from './esbuild/resolve_plugin.js'
import ArgumentError from './esbuild/argument_error.js'

if (import.meta.main) {
  const { _: paths, ...options } = parseArgs(Deno.args, {
    string: ['root', 'runtime-dir'],
    boolean: ['write'],
    alias: { 'runtime-dir': 'runtimeDir' }
  })
  await writeAll(Deno.stdout, await main(paths, options))
}

async function main(paths = [], options = {}) {
  const { root, write } = { write: false, ...options }

  if (!Array.isArray(paths) || paths.length < 1) throw new ArgumentError('pathsRequired')
  if (!root) throw new ArgumentError('rootRequired')

  // Make sure that `root` is a valid directory.
  try {
    const stat = Deno.lstatSync(root)
    if (!stat.isDirectory) throw new ArgumentError('rootUnknown', { root })
  } catch {
    throw new ArgumentError('rootUnknown', { root })
  }

  const isProd = Deno.env.get('RAILS_ENV') === 'production'

  const entryPoints = new Set()
  for (let i = 0; i < paths.length; i++) {
    const path = paths[i]

    if (isGlob(path)) {
      for await (const file of expandGlob(path, { root })) {
        file.isFile && entryPoints.add(file.path)
      }
    } else {
      entryPoints.add(join(root, path))
    }
  }

  const runtimeDir = resolve(dirname(fromFileUrl(import.meta.url)), '../runtime')

  const params = {
    entryPoints: Array.from(entryPoints),
    absWorkingDir: root,
    logLevel: 'error',
    sourcemap: isProd ? 'linked' : 'inline',
    outdir: 'public/assets',
    outbase: './',
    format: 'esm',
    jsxFactory: 'reactCreateElement',
    jsxFragment: 'ReactFragment',
    minify: isProd,
    bundle: true,
    plugins: [envPlugin(), resolvePlugin({ runtimeDir, debug: false })],
    inject: [join(runtimeDir, 'react_shim/index.js')],
    metafile: write,
    write
  }

  try {
    const result = await build(params)

    if (write) {
      return new TextEncoder().encode(JSON.stringify(result))
    } else {
      return result.outputFiles[0].contents
    }
  } finally {
    stop()
  }
}

export default main
