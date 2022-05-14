# Ibiza - React State Management for Party Animals

Ibiza gets out of your way and simply lets you read and write state as you would with regular
Javascript assignment. It maintains a global state object and is smart enough to know when to
rerender your components based on state usage and modification.

## `useIbiza()` ✨

A component calls the `useIbiza` React hook, which returns the store state as a JS Proxy object.
This Proxy records when a state property is accessed or "used". Then when that property is mutated,
the component is rerendered.

This means that you can mutate your state in any way, but your component will only rerender if you
mutate state that you have used.

The following component will rerender when the button is clicked, because `name` has changed.

```jsx
import { useIbiza } from 'ibiza'

const App = () => {
  const state = useIbiza()

  return (
    <div>
      <h1>Hello {state.name}</h1>
      <button onClick={() => void (state.name = 'Joel')}></button>
    </div>
  )
}
```

The following component will not rerender when the button is clicked, because even though `age` has
been mutated, it is not actually being used within the component.

```jsx
import { useIbiza } from 'ibiza'

const App = () => {
  const state = useIbiza()

  return (
    <div>
      <h1>Hello {state.name}</h1>
      <button onClick={() => void (state.age = 44)}></button>
    </div>
  )
}
```

State can be mutated from anywhere - not just from within a component:

```js
import { useIbiza, store } from 'ibiza'

const App = () => {
  const state = useIbiza()

  return (
    <div>
      <h1>Hello {state.name}</h1>
    </div>
  )
}

// <App> component will re-render when this line executes, as `name` has changed.
store.state.name = 'Ash'
```

### Initial State

You can pass some initial state to `useIbiza` which will be merged with existing state in the Ibiza
store.

```jsx
const App = () => {
  const state = useIbiza({ user: { name: 'Joel' } })

  return <h1>Hello {state.user.name}</h1>
}
```

This is safe to include in the body of your component, as it will only be merged into the store on
first render.

### Slicing

Ibiza supports deeply nested objects, allowing you to design the shape of your state any way you
like. To help you work with such nested state, the `useIbiza` hook supports slicing.

The following example assumes you have an existing state object:

```javascript
{
  user: {
    name: 'Joel',
    partner: {
      name: 'Sam',
    }
  }
}
```

Pass a string to `useIbiza` to fetch a specific slice of state. The string should be the path to the
object that you want.

```jsx
const App = () => {
  const partner = useIbiza('user.partner')

  return (
    <div>
      <h1>Hello {partner.name}</h1>
      <button onClick={() => void (partner.name = 'Bob')}></button>
    </div>
  )
}
```

Note that slicing is really only supported as a convenience, and will not generally help with
performance.

## `createModel()`

Ibiza is at its most powerful when working with models. They provide reusability and flexibility.

Create a model using the `createModel` helper, where the first argument is the model name, and the
second argument is the initial model state as a plain object.

```javascript
// model.js

export default createModel('user', {
  firstName: 'Joel',
  lastName: 'Moss',
  children: [{ firstName: 'Ash' }, { firstName: 'Elijah' }, { firstName: 'Eve' }]
})
```

`createModel` returns a hook which you can use. You can now import your model anywhere:

```jsx
// app.jsx

import useModel from './model'

const App = () => {
  const user = useModel()

  return (
    <div>
      <h1>Hello {user.firstName}</h1>
      <ul>
        {user.children.map((child, i) => (
          <li key={i}>{child.firstName}</li>
        ))}
      </ul>
    </div>
  )
}
```

### Initial State

Sometimes you want to be able to define your model with some initial state that could be provided
dynamically. For example, from component props or some other parameters.

`createModel` can accept a function as its second argument. This function will be called on
initialisation with two arguments; the current `state` and any `props` passed to it when its hook is
first called.

```javascript
// model.js

export default createModel('user', (state, props) => ({
  firstName: 'Joel',
  lastName: 'Moss'
  ...props
}))
```

```jsx
// app.jsx

import useModel from './model'

const App = ({ yearOfBirth }) => {
  const user = useModel({ yearOfBirth })

  return (
    <div>
      <h1>
        Hello {user.firstName}, you were born in {user.yearOfBirth}.
      </h1>
    </div>
  )
}
```

### Functions

You can use regular function in your model. They accept the current state as the first argument, and
`this` will also be the current state (as long as you don't use hash rocket functions).

```jsx
const App = () => {
  const state = useIbiza({
    count: 0,
    increment: state => {
      ++state.count
    },
    decrement() {
      ++this.count
    }
  })

  return (
    <>
      <h1>Count = {state.count}</h1>
      <button onClick={state.increment}>Increment</button>
      <button onClick={state.decrement}>Decrement</button>
    </>
  )
}
```

When reading/writing state within a function, `this` responds to the state at the level where the
function sits. This means that if the function is deeply nested, `this` will not include state lower
down.

To solve this, you can call `this.$model` to access your model, or `this.$root` to access the root
of the store state.

```javascript
useIbiza({
  deepstate: {
    user: {
      name: 'Joel',
      partner: {
        name: 'Sam',

        get partner() {
          // `this` refers to 'deepstate.user.partner'.
          // `this.$model` refers to 'deepstate.user'.
          // `this.$root` is the whole store state.
          return this.$model.name
        }
      }
    }
  }
})
```

Functions accept any number of arguments just like regular functions do, but don't forget that the
first argument is always the state.

```jsx
const App = () => {
  const user = useIbiza({
    children: [],
    addChild(state, firstName, lastName) {
      state.children.push({ firstName, lastName }) // or `this.children.push(...)`
    }
  })

  return (
    <>
      <ul>
        {user.children.map((child, i) => (
          <li key={i}>
            {child.firstName} {child.lastName}
          </li>
        ))}
      </ul>
      <button onClick={() => user.addChild('Ash', 'Moss')}></button>
    </>
  )
}
```

### Getters and Setters

Ibiza supports Javascript getters and setters in your state and models.

```javascript
export default createModel('user', {
  firstName: 'Joel',
  lastName: 'Moss',

  get fullName() {
    // You can read/write to your state via `this`.
    return `${this.firstName} ${this.lastName}`
  },

  set fullName(value) {
    const [firstName, lastName] = value.split(' ')

    this.firstName = firstName
    this.lastName = lastName
  }
})
```

```jsx
import useModel from './user_model'

const App = () => {
  const user = useModel()

  return (
    <>
      <h1>Hello {user.fullName}</h1>
      <button onClick={() => void (user.fullName = 'Bob Bones')}></button>
    </>
  )
}
```

### Async Functions

Functions can be async and/or return Promises, and support React's Suspense by default.

```javascript
export default createModel('user', {
  name: 'Joel',

  async doSomething() {
    return await someAsyncAction()
  }
})
```

```jsx
import useModel from './user_model'

const App = () => {
  const user = useModel()

  return (
    <>
      <h1>Hello {user.fullName}</h1>
      <button onClick={user.doSomething}></button>
    </>
  )
}
```

### URL Models

Because reading and writing to/from the server is so common, Ibiza has support to make this easy
with URL Models, similar to react-query. Simply use a valid and relative URL as your model name or
slice.

The following will fetch the user from the server at `/user`, suspending the component while it does
so. The data is fetched only when it does not exist in the store.

```jsx
const App = () => {
  const user = useIbiza('/user')

  return <h1>Hello {user.name}</h1>
}
```

You can safely mutate your model, as all mutations will remain local.

You can write your model state back to the server. It the server responds with JSON, the model will
be updated with that response.

```jsx
const App = () => {
  const user = useIbiza('/user')

  const renameUser = async () => {
    await user.save({ body: { name: 'Bob' } })
  }

  return (
    <>
      <h1>Hello {user.name}</h1>
      <button onClick={renameUser}></button>
    </>
  )
}
```

URL Models can also be defined with `createModel`, and accept the same arguments:

```javascript
export default createModel('/user')
```

`createModel` returns a hook which you can use. You can now import your model anywhere:

```jsx
import useModel from './user_model'

const App = () => {
  const user = useModel()

  return <h1>Hello {user.firstName}</h1>
}
```

Additionally, URL models accept a `fetcher` option, which when provided, will be used as the fetch
function for the model:

```javascript
export default createModel('/user', {}, { fetcher: myFetchFunction })
```
