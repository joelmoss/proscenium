export async function fileExists(path) {
  try {
    const fileInfo = await Deno.stat(path)
    return fileInfo.isFile
  } catch {
    return false
  }
}
