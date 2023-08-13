const elements = document.querySelectorAll("[data-proscenium-component-path]");

// Initialize if there are components.
elements.length > 0 && init();

function init() {
  function mount(element, path, props) {
    const react = import("@proscenium/react-manager/react");
    const component = window.prosceniumComponents[path];
    const Component = import(component.outpath);

    Promise.all([react, Component]).then(([r, c]) => {
      if (proscenium.env.RAILS_ENV === "development") {
        console.groupCollapsed(
          `[proscenium/component-manager] 🔥 %o mounted!`,
          path
        );
        console.log("props: %o", props);
        console.groupEnd();
      }

      r.createRoot(element).render(r.createElement(c.default, props));
    });
  }

  Array.from(elements, (element) => {
    const path = element.dataset.prosceniumComponentPath;
    const isLazy = "prosceniumComponentLazy" in element.dataset;
    const { children, ...props } = JSON.parse(
      element.dataset.prosceniumComponentProps
    );

    if (proscenium.env.RAILS_ENV === "development") {
      console.groupCollapsed(
        isLazy
          ? `[proscenium/component-manager] 💤 %o`
          : `[proscenium/component-manager] ⚡️ %o`,
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
}
