# Proscenium / Component Manager

> Lazy load islands of React components.

## Install

`npm add @proscenium/component-manager` or

`yarn add @proscenium/component-manager` or

`pnpm add @proscenium/component-manager`

## Usage

**NOTE: `component-manager` is designed to be used with [proscenium](https://github.com/joelmoss/proscenium)**

Wherever you want to render a component, simply create an HTML element with the class
`componentManagedByProscenium`, and a `data-component` attribute. The `init()` function will then
find these elements you created, and will lazily load and render the matching component in their
place.

The `data-component` attribute should be a stringified JSON object and defines where the component
module should be imported from, the props it should be given, and any other options.

```json
{
  "path": "my/component",
  "props": {
    "name": "Joel"
  },
  "lazy": true // default
}
```

At a minimum, the `path` to the component should be given, and will be used to import the component.

By default, components are only loaded and rendered when coming into view using the browser's
`IntersectionObserver`. You can disable this and render a component immediately by passing
`lazy: false`.

## Example

```html
<div
  class="componentManagedByProscenium"
  data-component="{\"path\":\"my/component\",\"lazy\":true,\"props\":{\"name\":\"Joel\"}}">
  loading...
</div>
```

```js
import init from '@proscenium/component-manager'

init({
  // Wrap all components with this component.
  //
  // If a String, it should be a path to a module that will be dynamically imported and wrapped with
  // React's `lazy` helper. If a function, that function should return a dynamic `import()` of the
  // component you want to wrap with. If a promise, it should be the result of a dynamic `import()`.
  wrapWithComponent: '/my/application/component.jsx',

  // Wrap each components with this component.
  //
  // If a String, it should be a path to a module that will be dynamically imported and wrapped with
  // React's `lazy` helper. If a function, that function should return a dynamic `import()` of the
  // component you want to wrap with. If a promise, it should be the result of a dynamic `import()`.
  wrapEachWithComponent: '/my/each/component.jsx',

  // The Node selector to use for querying for components.
  selector: '.componentManagedByProscenium',

  // A function that accepts the component path, and should return a new path. This allows you to
  // rewrite the import path to your components.
  //
  // Example
  //  my/component -> /components/my/component.jsx
  buildComponentPath(component) {
    return `/components/${component}.jsx`
  },

  debug: false
})
```
