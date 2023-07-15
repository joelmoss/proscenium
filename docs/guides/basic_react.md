# Render a React component with Proscenium

This guide will walk you through creating a simple [React](https://react.dev) component with Proscenium in a Rails application.

## Prerequisites

It is assumed that you have already [installed Proscenium](/README.md#installation) in your Rails app, and are [side loading your client assets](/README.md#side-loading) through the use of the `side_load_javascripts` helper.

It also requires that you have a JavaScript package manager installed, such as [NPM](https://www.npmjs.com/), [Yarn](https://yarnpkg.com/) or [Pnpm](https://pnpm.io/). You could also import React from any good CDN. We will use NPM in this guide. Feel free to use the package manager of your choice.

## Install React

Install the react and react-dom packages:

```bash
npm add react react-dom
```

## Creating a React component

First let's create a simple controller and view within which we will render our React component.

```bash
rails g controller home index
```

We'll create a simple component that will render a "Hello from React!" message onto the page.

Create a new file alongside your newly created view at `app/views/home` directory called `index.jsx` and add the following code:

```jsx
import { createRoot } from "react-dom/client";

const Component = () => <h1>Hello from React!</h1>;

const root = createRoot(document.getElementById("root"));

root.render(<Component />);
```

Now open up the `app/views/home/index.html.erb` file and add a `<div>` element with an ID of `root`. This is where our React component will be rendered.

```html
<div id="root"></div>
```

When we start our Rails app with `bundle exec rails s` and go to http://localhost:3000/home/index, we'll see our "Hello from React!" message.

## And We're Done! 🎉

That's it! You've successfully created a React component in your Rails app using Proscenium.
