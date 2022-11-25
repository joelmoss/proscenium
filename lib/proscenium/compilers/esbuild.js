import { writeAll } from 'std/streams/mod.ts'
import { parse as parseArgs } from 'std/flags/mod.ts'
import { expandGlob } from 'std/fs/mod.ts'
import { join, isGlob, resolve, dirname, fromFileUrl } from 'std/path/mod.ts'
import { build, stop } from 'esbuild'

import readImportMap from './esbuild/import_map/read.js'
import envPlugin from './esbuild/env_plugin.js'
import cssPlugin from './esbuild/css_plugin.js'
import resolvePlugin from './esbuild/resolve_plugin.js'
import ArgumentError from './esbuild/argument_error.js'
import throwCompileError from './esbuild/compile_error.js'

/**
 * Compile the given paths, outputting the result to stdout. This is designed to be called as a CLI:
 *
 * Example with Deno run (dev and test):
 *  deno run -A lib/proscenium/compilers/esbuild.js --root ./test/internal lib/foo.js
 * Example with Deno compiled binary:
 *  bin/esbuild lib/proscenium/compilers/esbuild.js --root ./test/internal lib/foo.js
 *
 * USAGE:
 *   esbuild [OPTIONS] <PATHS_ARG>...
 *
 * ARGS:
 *   <PATHS_ARG>... One or more file paths or globs to compile.
 *
 * OPTIONS:
 *   --root <PATH>
 *       Relative or absolute path to the root or current working directory when compilation will
 *       take place.
 *   --import-map <PATH>
 *       Path to an import map, relative to the <root>.
 *   --lightningcss-bin <PATH>
 *       Path to the lightningcss CLI binary.
 *   --write
 *       Write output to the filesystem according to esbuild logic.
 *   --cache-query-string <STRING>
 *       Query string to append to all imports as a cache buster. Example: `v1`.
 *   --debug
 *       Debug output,
 */
if (import.meta.main) {
  !Deno.env.get('RAILS_ENV') && Deno.env.set('RAILS_ENV', 'development')

  const { _: paths, ...options } = parseArgs(Deno.args, {
    string: ['root', 'import-map', 'lightningcss-bin', 'cache-query-string'],
    boolean: ['write', 'debug'],
    alias: {
      'import-map': 'importMap',
      'cache-query-string': 'cacheQueryString',
      'lightningcss-bin': 'lightningcssBin'
    }
  })

  let result = await main(paths, options)

  // `result` is an error object, so return to stderr as JSON, and an exit code of 1.
  if (isPlainObject(result)) {
    result = new TextEncoder().encode(`
      (${throwCompileError()})(${JSON.stringify(result)});
      export default null;
    `)
  }

  await writeAll(Deno.stdout, result)
}

async function main(paths = [], options = {}) {
  const { write, debug } = { write: false, ...options }

  if (!Array.isArray(paths) || paths.length < 1) throw new ArgumentError('pathsRequired')
  if (!options.root) throw new ArgumentError('rootRequired')
  if (!options.lightningcssBin) throw new ArgumentError('lightningcssBinRequired')

  const root = resolve(options.root)

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
  let isSourceMap = false

  // Loop through all the paths, and add each as an entrypoint. If any end with ".map", it is a
  // request for a sourcemap. In this case, we strip the '.map' off the end of the path so that
  // esbuild can compile it as usual. The esbuild `sourceMap` option is then set to 'external'.
  for (let i = 0; i < paths.length; i++) {
    const path = paths[i]

    if (isGlob(path)) {
      for await (const file of expandGlob(path, { root })) {
        if (file.isFile) {
          if (file.path.endsWith('.map')) {
            entryPoints.add(file.path.slice(0, -4))
            isSourceMap = true
          } else {
            entryPoints.add(file.path)
          }
        }
      }
    } else if (path.startsWith('/') || /^url:https?:\/\//.test(path)) {
      // Path is absolute, or is prefixed with 'url:', so it must be outsideRoot, or Url. Don't
      // prefix the root.
      // See Proscenium::Middleware::[OutsideRoot|Url].
      if (path.endsWith('.map')) {
        entryPoints.add(path.slice(0, -4))
        isSourceMap = true
      } else {
        entryPoints.add(path)
      }
    } else {
      if (path.endsWith('.map')) {
        entryPoints.add(join(root, path.slice(0, -4)))
        isSourceMap = true
      } else {
        entryPoints.add(join(root, path))
      }
    }
  }

  let importMap
  try {
    importMap = readImportMap(options.importMap, root)
  } catch (error) {
    return {
      detail: error.stack,
      text: `Cannot read/parse import map: ${error.message}`,
      location: {
        file: error.file
      }
    }
  }

  const runtimeDir = resolve(dirname(fromFileUrl(import.meta.url)), '../runtime')

  const params = {
    entryPoints: Array.from(entryPoints),
    absWorkingDir: root,
    logLevel: 'silent',
    logLimit: 1,
    outdir: 'public/assets',
    outbase: './',
    format: 'esm',
    jsx: 'automatic',
    jsxDev: !isTest && !isProd,
    minify: !isTest,
    bundle: true,
    sourcemap: isSourceMap ? 'external' : 'linked',

    // The Esbuild default places browser before module, but we're building for modern browsers
    // which support esm. So we prioritise that. Some libraries export a "browser" build that still
    // uses CJS.
    mainFields: ['module', 'browser', 'main'],

    plugins: [
      envPlugin(),
      resolvePlugin({ runtimeDir, importMap, debug, cacheQueryString: options.cacheQueryString }),
      cssPlugin({ lightningcssBin: options.lightningcssBin, debug })
    ],
    metafile: write,
    write
  }

  let result
  try {
    result = await build(params)
  } catch (error) {
    if (debug) {
      throw error
    }

    return { ...error.errors[0] }
  } finally {
    stop()
  }

  if (write) {
    return new TextEncoder().encode(JSON.stringify(result))
  } else {
    const fileIndex = params.sourcemap === 'linked' ? 1 : 0
    return result.outputFiles[fileIndex].contents
  }
}

export function isPlainObject(value) {
  if (Object.prototype.toString.call(value) !== '[object Object]') return false

  const prototype = Object.getPrototypeOf(value)
  return prototype === null || prototype === Object.prototype
}

export default main
