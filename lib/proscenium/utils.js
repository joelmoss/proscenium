import { resolve as resolvePath } from 'std/path/mod.ts'
import { resolvePath as resolvePathFromImportMap } from './compilers/esbuild/import_map/resolver.js'

export const httpRegex = /^https?:\/\//

export async function fileExists(path) {
  try {
    const fileInfo = await Deno.stat(path)
    return fileInfo.isFile
  } catch {
    return false
  }
}

export function isBareModule(mod) {
  return !mod.startsWith('/') && !mod.startsWith('.')
}

const loaderMap = {
  '.css': 'css',
  '.js': 'js',
  '.svg': 'text'
}
export function loaderType(filename) {
  const key = Object.keys(loaderMap).find(ext => filename.endsWith(ext))
  return loaderMap[key]
}

// Read a file and returns its contents. This exists to raise a more useful error message when it
// fails.
export async function readFile(path) {
  try {
    return await Deno.readTextFile(path)
  } catch (error) {
    throw new Error(`No such file: ${path}`, { cause: error })
  }
}

// Resolve with import map - if any
export function resolveWithImportMap(importMap, params, cwd) {
  if (!importMap) return

  let baseURL
  if (httpRegex.test(params.importer)) {
    baseURL = new URL(params.importer)
  } else {
    baseURL = new URL(params.importer.slice(cwd.length), 'file://')
  }

  const { matched, resolvedImport } = resolvePathFromImportMap(params.path, importMap, baseURL)

  if (matched) {
    if (resolvedImport instanceof URL) {
      if (resolvedImport.protocol === 'file:') {
        return resolvedImport.pathname
      } else {
        return resolvedImport.href
      }
    } else {
      return resolvedImport
    }
  }
}

export async function resolveImport(params, build, importMap) {
  const cwd = build.initialOptions.absWorkingDir

  let result = { path: params.path, suffix: params.suffix }

  // Resolve with import map - if any
  const mappedPath = resolveWithImportMap(importMap, params, cwd)
  if (mappedPath) {
    if (httpRegex.test(mappedPath)) {
      return { path: mappedPath }
    } else {
      result.path = mappedPath
    }
  }

  // TODO: This improves performance, as it avoids a build.resolve() call. But it only works if
  // `sideEffects`is false, which only `build.resolve()` knows about.
  //
  // if (result.path.startsWith('.')) {
  //   return { path: resolvePath(params.resolveDir, result.path), sideEffects: false }
  // }

  // Absolute path - append to current working dir. This allows absolute path imports
  // (eg, import '/lib/foo').
  if (result.path.startsWith('/')) {
    result.path = resolvePath(cwd, result.path.slice(1))
  }

  const resOptions = {
    resolveDir: params.resolveDir,
    importer: params.importer,
    kind: 'import-statement',

    // We use this property later on, as we should ignore this resolution call.
    pluginData: { isResolvingPath: true }
  }

  // Rewrite the resolveDir to cwd if it is the runtimeDir.
  if (params.resolveDir.startsWith(params.runtimeDir)) {
    resOptions.resolveDir = cwd
  }

  result = await build.resolve(result.path, resOptions)

  if (result.errors.length > 0) return result

  delete result.namespace

  return result
}
