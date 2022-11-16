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
