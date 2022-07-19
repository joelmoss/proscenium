/* eslint-disable no-console */

import { RAILS_ENV } from 'env'

// We don't use JSX, as doing so would auto-inject React. We don't want to do this, as React is lazy
// loaded only when needed.
export default async function (ele, data) {
  const { createElement, useEffect, lazy, Suspense } = await import('react')
  const { createRoot } = await import('react-dom/client')

  const component = lazy(() => import(`/app/components${data.path}.jsx`))
  const contentLoader = data.contentLoader && ele.firstElementChild

  const Fallback = ({ contentLoader }) => {
    useEffect(() => {
      contentLoader && contentLoader.remove()
    }, []) // eslint-disable-line react-hooks/exhaustive-deps

    if (!contentLoader) return null

    return /* @__PURE__ */ createElement('div', {
      style: { height: '100%' },
      dangerouslySetInnerHTML: { __html: contentLoader.outerHTML }
    })
  }

  createRoot(ele).render(
    /* @__PURE__ */ createElement(
      Suspense,
      {
        fallback: /* @__PURE__ */ createElement(Fallback, {
          contentLoader
        })
      },
      createElement(component, data.props)
    )
  )

  RAILS_ENV === 'development' && console.debug(`[REACT]`, `Rendered ${data.path.slice(1)}`)
}
