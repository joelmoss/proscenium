# Proscenium Component Manager

> Lazy load islands of React components.

```html
<div class="componentManagedByProscenium" data-component="{\"path\":\"my/component\",\"lazy\":true,\"props\":{\"name\":\"Joel\"}}">
  loading...
</div>
```

```js
import { init } from '@proscenium/component-manager'
init({
  // Wrap all components with wrapping component.
  wrapWith: lazy(() => import('my/application/component)),

  // The Node selector to use for querying for components.
  selector: '.componentManagedByProscenium',

  // A function that accepts the component path, and should return a new path. This allows you to
  // customise the path to your components.
  buildComponentPath(component) {
    return `/components/${component}.jsx`
  },

  debug: false
})
```
