/* eslint-disable no-console */

import { PROSCENIUM_APPLICATION_COMPONENT, RAILS_ENV } from 'env'

const shouldUseAppComponent = PROSCENIUM_APPLICATION_COMPONENT === 'true'

// We don't use JSX, as doing so would auto-inject React. We don't want to do this, as React is lazy
// loaded only when needed.
export default async function (ele, data) {
  const { useEffect, lazy, Suspense } = await import('react')
  const { createRoot } = await import('react-dom/client')

  const AppComponent = lazy(() => import(`/app/components/application.jsx`))
  const Component = lazy(() => import(`/app/components${data.path}.jsx`))
  const contentLoader = data.contentLoader && ele.firstElementChild

  const WrapWithAppComponent = ({ children }) => {
    return shouldUseAppComponent ? <AppComponent>{children}</AppComponent> : children
  }

  const Fallback = ({ contentLoader }) => {
    useEffect(() => {
      contentLoader && contentLoader.remove()
    }, []) // eslint-disable-line react-hooks/exhaustive-deps

    if (!contentLoader) return null

    return (
      <div
        style={{ height: '100%' }}
        dangerouslySetInnerHTML={{ __html: contentLoader.outerHTML }}
      ></div>
    )
  }

  createRoot(ele).render(
    <Suspense fallback={<Fallback contentLoader={contentLoader} />}>
      <WrapWithAppComponent>
        <Component {...data.props} />
      </WrapWithAppComponent>
    </Suspense>
  )

  RAILS_ENV === 'development' &&
    console.debug(`[Proscenium]`, `Rendered react:${data.path.slice(1)}`)
}
