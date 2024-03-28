export function lazyLoadControllersFrom(under, app, element = document) {
  const { controllerAttribute } = app.schema;

  lazyLoadExistingControllers(element);

  // Lazy load new controllers.
  new MutationObserver((mutationsList) => {
    for (const { attributeName, target, type } of mutationsList) {
      switch (type) {
        case "attributes": {
          if (
            attributeName == controllerAttribute &&
            target.getAttribute(controllerAttribute)
          ) {
            extractControllerNamesFrom(target).forEach((controllerName) =>
              loadController(controllerName)
            );
          }
        }

        case "childList": {
          lazyLoadExistingControllers(target);
        }
      }
    }
  }).observe(element, {
    attributeFilter: [controllerAttribute],
    subtree: true,
    childList: true,
  });

  function lazyLoadExistingControllers(element) {
    Array.from(element.querySelectorAll(`[${controllerAttribute}]`))
      .map(extractControllerNamesFrom)
      .flat()
      .forEach(loadController);
  }

  function extractControllerNamesFrom(element) {
    return element
      .getAttribute(controllerAttribute)
      .split(/\s+/)
      .filter((content) => content.length);
  }

  function loadController(name) {
    if (canRegisterController(name)) {
      const fileToImport = `${under}/${name
        .replace(/--/g, "/")
        .replace(/-/g, "_")}_controller.js`;

      import(fileToImport)
        .then((module) => {
          canRegisterController(name) && app.register(name, module.default);
        })
        .catch((error) =>
          console.error(`Failed to autoload controller: ${name}`, error)
        );
    }
  }

  function canRegisterController(name) {
    return !app.router.modulesByIdentifier.has(name);
  }
}
