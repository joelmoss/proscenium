import { writeAll } from 'std/streams/write_all.ts'
import { parse as parseArgs } from 'std/flags/mod.ts'
import { join, resolve, extname, basename, dirname, fromFileUrl } from 'std/path/mod.ts'
import { build, stop } from 'esbuild'

import readImportMap from './esbuild/import_map/read.js'
import envPlugin from './esbuild/env_plugin.js'
import cssPlugin from './esbuild/css_plugin.js'
import resolvePlugin from './esbuild/resolve_plugin.js'
import ArgumentError from './esbuild/argument_error.js'

const urlRegex = /^url:https?:\/\//
const npmRegex = /^npm:/

/**
 * Compile the given path, outputting the result to stdout. This is designed to be called as a CLI:
 *
 * Example with Deno run (dev and test):
 *  deno run -A lib/proscenium/compilers/esbuild.js --root ./test/internal lib/foo.js
 * Example with Deno compiled binary:
 *  bin/esbuild lib/proscenium/compilers/esbuild.js --root ./test/internal lib/foo.js
 *
 * USAGE:
 *   esbuild [OPTIONS] <PATH_ARG>...
 *
 * ARGS:
 *   <PATH_ARG>... A relative path of the file to compile.
 *
 * OPTIONS:
 *   --root <PATH>
 *       Relative or absolute path to the root or current working directory where compilation and
 *       module resolution will take place.
 *   --import-map <PATH>
 *       Path to an import map, relative to the <root>.
 *   --lightningcss-bin <PATH>
 *       Path to the lightningcss bin.
 *   --write
 *       Write output to the filesystem according to esbuild logic.
 *   --cache-query-string <STRING>
 *       Query string to append to all imports as a cache buster. Example: `v1`.
 *   --debug
 *       Debug output,
 */
if (import.meta.main) {
  !Deno.env.get('RAILS_ENV') && Deno.env.set('RAILS_ENV', 'development')

  const { _: path, ...options } = parseArgs(Deno.args, {
    string: ['root', 'import-map', 'lightningcss-bin', 'cache-query-string', 'css-mixin-path'],
    boolean: ['write', 'debug'],
    collect: ['css-mixin-path'],
    alias: {
      'import-map': 'importMap',
      'css-mixin-path': 'cssMixinPaths',
      'cache-query-string': 'cacheQueryString',
      'lightningcss-bin': 'lightningcssBin'
    }
  })

  let result = await main(path[0], options)

  // `result` is an error object. If request is for CSS, then return the error object as JSON to
  // stderr. Else throw a CompileError to stdout.
  if (isPlainObject(result)) {
    if (path[0].endsWith('.css')) {
      await writeAll(Deno.stderr, new TextEncoder().encode(JSON.stringify(result)))
    } else {
      let message = result.text
      if (result.location !== null) {
        message += ` at /${result.location.file}:${result.location.line}`
      }

      result = new TextEncoder().encode(
        [
          'class CompileError extends Error {',
          'constructor(message) { super(message);this.name = "CompileError"; }};',
          `throw new CompileError(\`${message}\`, { cause: ${JSON.stringify(result)} });`,
          'export default null;'
        ].join('')
      )

      await writeAll(Deno.stdout, result)
    }
  } else {
    await writeAll(Deno.stdout, result)
  }
}

async function main(path, options = {}) {
  const { root, write, debug } = { write: false, ...options }

  if (!path || path.length < 1) throw new ArgumentError('pathRequired')
  if (!root) throw new ArgumentError('rootRequired')
  if (!options.lightningcssBin) throw new ArgumentError('lightningcssBinRequired')

  const env = Deno.env.get('RAILS_ENV')
  const isProd = env === 'production'
  const isTest = env === 'test'
  const isRuntime = path.startsWith('proscenium-runtime')
  const isUrl = urlRegex.test(path)
  const isNpm = npmRegex.test(path)
  let entryPoint = ''
  let isSourceMap = false

  // If entryPoint ends with ".map", it is a request for a sourcemap. In this case, we strip the
  // '.map' off the end of the path so that esbuild can compile it as usual. The esbuild `sourceMap`
  // option is then set to 'external'.
  //
  // Also don't prefix the root for 'url:' or 'npm:' prefixed paths.
  if (path.endsWith('.map')) {
    entryPoint = isUrl || isNpm ? path.slice(0, -4) : join(root, path.slice(0, -4))
    isSourceMap = true
  } else {
    entryPoint = isUrl || isNpm ? path : join(root, path)
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
    entryPoints: [entryPoint],
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
    sourcemap: !isRuntime && isSourceMap ? 'external' : false,

    external: [
      '*.rjs', // This doesn't seem to work reliably, so the resolve plugin reimplements it.
      '*.gif'
    ],

    loader: {
      '.svg': 'text'
    },

    // Enabled to support symlinked node_modules (PNPM)
    preserveSymlinks: true,

    // The Esbuild default places browser before module, but we're building for modern browsers
    // which support esm. So we prioritise that. Some libraries export a "browser" build that still
    // uses CJS.
    mainFields: ['module', 'browser', 'main'],

    plugins: [
      envPlugin(),
      resolvePlugin({
        runtimeDir,
        importMap,
        debug,
        cacheQueryString: options.cacheQueryString
      }),
      cssPlugin({
        lightningcssBin: options.lightningcssBin,
        mixinPaths: options.cssMixinPaths,
        debug
      })
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
    if (isRuntime || isSourceMap) {
      return result.outputFiles[0].contents
    } else {
      let { path, text } = result.outputFiles[0]
      let sourcemapUrl = basename(entryPoint)

      if (isUrl) {
        sourcemapUrl = `/url:${encodeURIComponent(entryPoint.slice(4))}`
      } else if (!extname(entryPoint)) {
        sourcemapUrl = basename(path)
      }

      if (path.endsWith('.css')) {
        text += `/*# sourceMappingURL=${sourcemapUrl}.map */`
      } else {
        text += `//# sourceMappingURL=${sourcemapUrl}.map`
      }

      return new TextEncoder().encode(text + '\n')
    }
  }
}

export function isPlainObject(value) {
  if (Object.prototype.toString.call(value) !== '[object Object]') return false

  const prototype = Object.getPrototypeOf(value)
  return prototype === null || prototype === Object.prototype
}

export default main
