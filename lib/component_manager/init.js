/* eslint-disable no-console */

async function init(opts = {}) {
  const options = {
    debug: false,
    selector: '.componentManagedByProscenium',
    buildComponentPath(x) {
      return x
    },
    ...opts
  }
  const nodes = document.querySelectorAll(options.selector)

  if (nodes.length < 1) return

  const { lazy, createElement } = await import('react')
  const { createRoot } = await import('react-dom/client')
  const Manager = lazy(() => import('./manager'))

  // Find our components to load.
  const components = Array.from(nodes, domElement => {
    const { path, props, ...params } = JSON.parse(domElement.dataset.component)

    if (options.debug) {
      console.groupCollapsed(`[proscenium/component-manager] Loading %o`, path)
      console.log({ props, ...params })
      console.groupEnd()
    }

    return {
      component: lazy(() => import(options.buildComponentPath(path))),
      props,
      domElement,
      ...params
    }
  })

  const rootEle = document.createElement('div')
  document.body.append(rootEle)
  createRoot(rootEle).render(createElement(Manager, { components, wrapper: options.wrapWith }))
}

export default init
