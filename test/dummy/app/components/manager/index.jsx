const elements = document.querySelectorAll("[data-proscenium-component-path]");

// Return now if there are no components.
elements.length > 0 && init();

async function init() {
  const { Suspense, lazy, createElement, createRoot } = await import("./react");

  Array.from(elements, (element) => {
    const path = element.dataset.prosceniumComponentPath;
    const { children, ...props } = JSON.parse(
      element.dataset.prosceniumComponentProps
    );
    const isLazy = element.dataset.prosceniumComponentLazy;

    if (proscenium.env.RAILS_ENV === "development") {
      console.groupCollapsed(`[proscenium/component-manager] Found %o`, path);
      console.log("element: %o", element);
      console.log("props: %o", props);
      console.groupEnd();
    }

    const root = createRoot(element);

    if (isLazy) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            observer.unobserve(element);

            root.render(
              createElement(
                lazy(() => import(path)),
                props
              )
            );
          }
        });
      });

      observer.observe(element);
    } else {
      root.render(
        createElement(
          lazy(() => import(path)),
          props
        )
      );
    }
  });
}
