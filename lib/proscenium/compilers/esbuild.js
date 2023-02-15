import { writeAll } from 'std/streams/write_all.ts'
import { parse as parseArgs } from 'std/flags/mod.ts'
import { join, resolve, extname, basename, dirname, fromFileUrl } from 'std/path/mod.ts'
import { build, stop } from 'esbuild'

import readImportMap from './esbuild/import_map/read.js'
import envPlugin from './esbuild/env_plugin.js'
import i18nPlugin from './esbuild/i18n_plugin.js'
import svgPlugin from './esbuild/svg_plugin.js'
import cssPlugin from './esbuild/css_plugin.js'
import bundleAllPlugin from './esbuild/bundle_all_plugin.js'
import bundlePlugin from './esbuild/bundle_plugin.js'
import npmPlugin from './esbuild/npm_plugin.js'
import gemPlugin from './esbuild/gem_plugin.js'
import importMapPlugin from './esbuild/import_map_plugin.js'
import resolvePlugin from './esbuild/resolve_plugin.js'
import ArgumentError from './esbuild/argument_error.js'

const urlRegex = /^url:https?:\/\//
const npmRegex = /^npm:/
const gemRegex = /^gem:/

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

  const result = await main(path[0], options)

  // If `result` is an error object, return the error object as JSON to stderr.
  //
  // TODO: find a way to raise a JS exception with this error.
  if (isPlainObject(result)) {
    await writeAll(Deno.stderr, new TextEncoder().encode(JSON.stringify(result)))
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
  const isGem = gemRegex.test(path)
  let entryPoint = ''
  let isSourceMap = false

  // If entryPoint ends with ".map", it is a request for a sourcemap. In this case, we strip the
  // '.map' off the end of the path so that esbuild can compile it as usual. The esbuild `sourceMap`
  // option is then set to 'external'.
  //
  // Also don't prefix the root to 'url:' or 'npm:' prefixed paths.
  if (path.endsWith('.map')) {
    entryPoint = isUrl || isNpm || isGem ? path.slice(0, -4) : join(root, path.slice(0, -4))
    isSourceMap = true
  } else {
    entryPoint = isUrl || isNpm || isGem ? path : join(root, path)
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
  const pluginOptions = {
    env,
    importMap,
    debug,
    runtimeDir,
    cacheQueryString: options.cacheQueryString
  }
  const cssPluginOptions = {
    customMedia: await getCustomMedia(root),
    lightningcssBin: options.lightningcssBin,
    mixinPaths: options.cssMixinPaths
  }
  const allPluginOptions = { ...pluginOptions, ...cssPluginOptions }

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
    minify: !debug && !isTest,
    define: { 'process.env.NODE_ENV': `"${env}"` },
    bundle: true,
    sourcemap: !isRuntime && isSourceMap ? 'external' : false,
    external: ['*.rjs', '*.gif', '*.jpg', '*.png', '*.woff2', '*.woff'],
    metafile: write,
    keepNames: !isProd,
    write,

    // The Esbuild default places browser before module, but we're building for modern browsers
    // which support esm. So we prioritise that. Some libraries export a "browser" build that still
    // uses CJS.
    mainFields: ['module', 'browser', 'main'],

    plugins: [
      i18nPlugin({ debug }),
      importMap && importMapPlugin(pluginOptions),
      svgPlugin(pluginOptions),
      bundleAllPlugin(allPluginOptions),
      bundlePlugin(allPluginOptions),
      envPlugin(),
      npmPlugin({ debug }),
      gemPlugin({ debug }),
      resolvePlugin(pluginOptions),
      cssPlugin(allPluginOptions)
    ].filter(Boolean)
  }

  let result
  try {
    result = await build(params)
  } catch (error) {
    if (!debug) return { ...error.errors[0] }

    throw error
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
        sourcemapUrl = isNpm ? `/${entryPoint}` : basename(path)
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

async function getCustomMedia(cwd) {
  try {
    return await Deno.readTextFile(join(cwd, 'config', 'custom_media_queries.css'))
  } catch {
    // do nothing, as we don't require custom media.
  }
}

export function isPlainObject(value) {
  if (Object.prototype.toString.call(value) !== '[object Object]') return false

  const prototype = Object.getPrototypeOf(value)
  return prototype === null || prototype === Object.prototype
}

export default main
