const pathAttribute = "data-proscenium-component-path";

// Find components already in the DOM.
const elements = document.querySelectorAll(`[${pathAttribute}]`);
elements.length > 0 && init(elements);

new MutationObserver((mutationsList) => {
  for (const { addedNodes } of mutationsList) {
    for (const ele of addedNodes) {
      if (ele.matches(`[${pathAttribute}]`)) {
        init([ele]);
      }
    }
  }
}).observe(document, {
  subtree: true,
  childList: true,
});

function init(elements) {
  Array.from(elements, (element) => {
    const path = element.dataset.prosceniumComponentPath;
    const isLazy = "prosceniumComponentLazy" in element.dataset;
    const props = JSON.parse(element.dataset.prosceniumComponentProps);

    if (proscenium.env.RAILS_ENV === "development") {
      console.groupCollapsed(
        `[proscenium/react/manager] ${isLazy ? "💤" : "⚡️"} %o`,
        path
      );
      console.log("element: %o", element);
      console.log("props: %o", props);
      console.groupEnd();
    }

    if (isLazy) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            observer.unobserve(element);

            mount(element, path, props);
          }
        });
      });

      observer.observe(element);
    } else {
      mount(element, path, props);
    }
  });

  /**
   * Mounts component located at `path`, into the DOM `element`.
   *
   * The element at which the component is mounted must have the following data attributes:
   *
   * - `data-proscenium-component-path`: The URL path to the component's source file.
   * - `data-proscenium-component-props`: JSON object of props to pass to the component.
   * - `data-proscenium-component-lazy`: If present, will lazily load the component when in view
   *   using IntersectionObserver.
   * - `data-proscenium-component-forward-children`: If the element should forward its `innerHTML`
   *   as the component's children prop.
   */
  function mount(element, path, { children, ...props }) {
    // For testing and simulation of slow connections.
    // const sim = new Promise((resolve) => setTimeout(resolve, 5000));

    const react = import("@rubygems/proscenium/react-manager/react");
    const Component = import(path);

    const forwardChildren =
      "prosceniumComponentForwardChildren" in element.dataset &&
      element.innerHTML !== "";

    Promise.all([react, Component])
      .then(([r, c]) => {
        if (proscenium.env.RAILS_ENV === "development") {
          console.groupCollapsed(
            `[proscenium/react/manager] 🔥 %o mounted!`,
            path
          );
          console.log("props: %o", props);
          console.groupEnd();
        }

        let component;
        if (forwardChildren) {
          component = r.createElement(c.default, props, element.innerHTML);
        } else if (children) {
          component = r.createElement(c.default, props, children);
        } else {
          component = r.createElement(c.default, props);
        }

        r.createRoot(element).render(component);
      })
      .catch((error) => {
        console.error("[proscenium/react/manager] %o - %o", path, error);
      });
  }
}
