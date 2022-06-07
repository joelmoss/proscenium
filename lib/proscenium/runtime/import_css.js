async function digest(value) {
  value = new TextEncoder().encode(value)
  const view = new DataView(await crypto.subtle.digest('SHA-1', value))

  let hexCodes = ''
  for (let index = 0; index < view.byteLength; index += 4) {
    hexCodes += view.getUint32(index).toString(16).padStart(8, '0')
  }

  return hexCodes.slice(0, 8)
}

const proxyCache = {}

export async function importCssModule(path) {
  appendStylesheet(path)

  if (Object.keys(proxyCache).includes(path)) {
    return proxyCache[path]
  }

  const hashValue = await digest(path)
  return (proxyCache[path] = new Proxy(
    {},
    {
      get(target, prop, receiver) {
        if (prop in target || typeof prop === 'symbol') {
          return Reflect.get(target, prop, receiver)
        } else {
          return `${prop}${hashValue}`
        }
      }
    }
  ))
}

export function appendStylesheet(path) {
  // Make sure we only load the stylesheet once.
  if (document.head.querySelector(`link[rel=stylesheet][href='${path}']`)) return

  const ele = document.createElement('link')
  ele.setAttribute('rel', 'stylesheet')
  ele.setAttribute('media', 'all')
  ele.setAttribute('href', path)
  document.head.appendChild(ele)
}
