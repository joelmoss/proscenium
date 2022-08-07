import { join } from 'std/path/mod.ts'
import { parseFromString } from 'import-maps/resolve'

const baseURL = new URL('file://')

class ImportMapError extends Error {
  constructor(fileName, ...params) {
    super(...params)

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, ImportMapError)
    }

    this.name = 'ImportMapError'
    this.file = fileName
  }
}

export function readImportMap(fileName, rootDir) {
  let importMap

  if (fileName) {
    importMap = readFile(fileName, rootDir, true)
  } else {
    fileName = ['config/import_map.json', 'config/import_map.js'].find(f => {
      const result = readFile(f, rootDir)
      if (result) {
        importMap = result
        return true
      }
    })
  }

  return importMap
}

function readFile(file, rootDir, required = false) {
  let contents = null

  try {
    contents = Deno.readTextFileSync(join(rootDir, file))
  } catch (error) {
    if (required) {
      throw new ImportMapError(file, error.message, { cause: error })
    }
  }

  if (contents === null) return null

  try {
    if (file.endsWith('.js')) {
      contents = JSON.stringify(eval(contents)(Deno.env.get('RAILS_ENV')))
    }

    return parseFromString(contents, baseURL)
  } catch (error) {
    throw new ImportMapError(file, error.message, { cause: error })
  }
}
