export default async path => {
  return await import(path, { assert: { type: 'css' } })
}
