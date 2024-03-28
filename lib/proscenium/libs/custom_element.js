/**
 * Base class for custom elements, providing support for event delegation, and idempotent
 * customElement registration.
 *
 * The `handleEvent` method is called any time an event defined in `delegatedEvents` is triggered.
 * It's a central handler to handle events for this custom element.
 *
 * @example
 *   class MyComponent extends CustomElement {
 *     static componentName = 'my-component'
 *     static delegatedEvents = ['click']
 *
 *     handleEvent(event) {
 *       console.log('Hello, world!')
 *     }
 *   }
 *   MyComponent.register()
 */
export default class CustomElement extends HTMLElement {
  /**
   * Register the component as a custom element, inferring the component name from the kebab-cased
   * class name. You can override the component name by setting a static `componentName` property.
   *
   * This method is idempotent.
   */
  static register() {
    if (this.componentName === undefined) {
      this.componentName = this.name
        .replaceAll(/(.)([A-Z])/g, "$1-$2")
        .toLowerCase();
    }

    if (!customElements.get(this.componentName)) {
      customElements.define(this.componentName, this);
    }
  }

  /**
   * A list of event types to be delegated for the lifetime of the custom element.
   *
   * @type {Array}
   */
  static delegatedEvents = [];

  constructor() {
    super();

    if (typeof this.handleEvent !== "undefined") {
      this.constructor.delegatedEvents?.forEach((event) => {
        this.addEventListener(event, this);
      });
    }
  }
}
