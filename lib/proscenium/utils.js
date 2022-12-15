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
  '.js': 'js'
}
export function loaderType(filename) {
  const key = Object.keys(loaderMap).find(ext => filename.endsWith(ext))
  return loaderMap[key]
}
