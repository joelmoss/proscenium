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
