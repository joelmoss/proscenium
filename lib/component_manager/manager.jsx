import { Suspense, createElement, useState, useEffect, useMemo } from 'react'
import { createPortal } from 'react-dom'

const Manager = ({ components, wrapper, debug }) => {
  const mappedComponents = components.map((comp, key) =>
    comp.lazy ? (
      <Observed key={key} debug={debug} {...comp} />
    ) : (
      <Portaled key={key} debug={debug} {...comp} />
    )
  )

  if (wrapper) {
    return createElement(wrapper, { debug, children: mappedComponents })
  } else {
    return <>{mappedComponents}</>
  }
}

const Portaled = ({ component, path, debug, domElement, props }) => {
  const content = domElement.hasChildNodes() && domElement.firstElementChild
  let shownDebugMsg = false

  useEffect(() => {
    if (debug && !shownDebugMsg) {
      shownDebugMsg = true
      console.groupCollapsed(`[proscenium/component-manager] Rendering %o`, path)
      console.log('domElement: %o', domElement)
      console.log('props: %o', props)
      console.groupEnd()
    }
  }, [])

  return createPortal(
    <Suspense fallback={<Fallback content={content} />}>
      {createElement(component, props)}
    </Suspense>,
    domElement
  )
}

const Observed = ({ domElement, debug, componentPath, ...comp }) => {
  const [isVisible, setIsVisible] = useState(false)
  const observer = useMemo(() => {
    return new IntersectionObserver(entries => {
      entries.forEach(entry => {
        !isVisible && entry.isIntersecting && setIsVisible(true)
      })
    })
  }, [isVisible])

  useEffect(() => {
    if (isVisible) {
      observer.unobserve(domElement)
      return
    }

    observer.observe(domElement)

    return () => observer.unobserve(domElement)
  }, [domElement, isVisible, observer])

  if (!isVisible) return null

  return <Portaled {...{ domElement, componentPath, debug }} {...comp} />
}

const Fallback = ({ content }) => {
  useEffect(() => {
    content?.remove()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  if (!content) return null

  return <div dangerouslySetInnerHTML={{ __html: content.outerHTML }} />
}

export default Manager
