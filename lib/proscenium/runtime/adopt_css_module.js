// Expects a `path` to a stylesheet as its only argument, and returns an Object of CSS classes to
// CSS modules.
export default async function (path) {
  const modules = {}
  let stylesheet = await import(path, { assert: { type: 'css' } })
  stylesheet = stylesheet.default

  for (let index = 0; index < stylesheet.cssRules.length; index++) {
    const rule = stylesheet.cssRules[index]

    if (rule.selectorText.startsWith('.')) {
      const [_className, ...rest] = rule.selectorText.split(' ')
      const className = _className.slice(1)
      const ident = await hash(`${path}|${className}`)

      modules[className] = `${className}${ident}`
      rule.selectorText = [`.${className}${ident}`, rest].join(' ')

      stylesheet.deleteRule(index)
      stylesheet.insertRule(rule.cssText, index)
    }
  }

  document.adoptedStyleSheets = [...document.adoptedStyleSheets, stylesheet]

  return modules
}

async function hash(value, length = 8) {
  value = new TextEncoder().encode(value)
  const view = new DataView(await crypto.subtle.digest('SHA-1', value))

  let hexCodes = ''
  for (let index = 0; index < view.byteLength; index += 4) {
    hexCodes += view.getUint32(index).toString(16).padStart(8, '0')
  }

  return hexCodes.slice(0, length)
}
