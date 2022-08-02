import { writeAll } from 'std/streams/mod.ts'
import { parse as parseArgs } from 'std/flags/mod.ts'
import { expandGlob } from 'std/fs/mod.ts'
import { join, isGlob, resolve, dirname, fromFileUrl } from 'std/path/mod.ts'
import { build, stop } from 'esbuild'

import envPlugin from './esbuild/env_plugin.js'
import resolvePlugin from './esbuild/resolve_plugin.js'
import ArgumentError from './esbuild/argument_error.js'
import throwCompileError from './esbuild/compile_error.js'

if (import.meta.main) {
  !Deno.env.get('RAILS_ENV') && Deno.env.set('RAILS_ENV', 'development')

  const { _: paths, ...options } = parseArgs(Deno.args, {
    string: ['root', 'runtime-dir'],
    boolean: ['write'],
    alias: { 'runtime-dir': 'runtimeDir' }
  })

  let result = await main(paths, options)

  // `result` is an error object, so return to stderr as JSON, and an exit code of 1.
  if (isPlainObject(result)) {
    result = new TextEncoder().encode(`(${throwCompileError()})(${JSON.stringify(result)})`)
  }

  await writeAll(Deno.stdout, result)
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

  const env = Deno.env.get('RAILS_ENV')
  const isProd = env === 'production'
  const isTest = env === 'test'

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
    logLevel: 'silent',
    sourcemap: isProd ? 'linked' : 'inline',
    outdir: 'public/assets',
    outbase: './',
    format: 'esm',
    jsx: 'automatic',
    jsxDev: !isTest && !isProd,
    minify: isProd,
    bundle: true,
    plugins: [envPlugin(), resolvePlugin({ runtimeDir, debug: false })],
    // inject: [join(runtimeDir, 'react_shim/index.js')],
    metafile: write,
    write
  }

  let result
  try {
    result = await build(params)
  } catch (error) {
    return { ...error.errors[0] }
  } finally {
    stop()
  }

  if (write) {
    return new TextEncoder().encode(JSON.stringify(result))
  } else {
    return result.outputFiles[0].contents
  }
}

export function isPlainObject(value) {
  if (Object.prototype.toString.call(value) !== '[object Object]') return false

  const prototype = Object.getPrototypeOf(value)
  return prototype === null || prototype === Object.prototype
}

export default main
