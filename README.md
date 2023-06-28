# Proscenium - Modern client-side development for Rails

Proscenium treats your client-side code as first class citizens of your Rails app, and assumes a
"fast by default" internet. It bundles your JS, JSX and CSS in real time, on demand, and with zero
configuration.

- Fast real-time bundling, tree-shaking and minification of Javascript (.js,.jsx), Typescript (.ts,.tsx) and CSS (.css).
- NO JavaScript runtime needed - just the browser!
- NO build step or pre-compilation.
- NO additional process or server - Just run Rails!
- Deep integration with Rails.
- Zero configuration.
- Serve assets from anywhere within your Rails root (/app, /config, /lib, etc.).
- Automatically side load JS/TS/CSS for your layouts and views.
- ESM importing from NPM, URLs, and locally.
- Server-side import map support.
- CSS Modules & mixins.
- Source maps.

## Table of Contents

- [Getting Started](#getting-started)
- [Installation](#installation)
- [Client-Side Code Anywhere](#client-side-code-anywhere)
- [Side Loading](#side-loading)
- [Importing](#importing-assets)
  - [URL Imports](#url-imports)
  - [Local Imports](#local-imports)
- [Import Maps](#import-maps)
- [Source Maps](#source-maps)
- [SVG](#svg)
- [Environment Variables](#environment-variables)
- [i18n](#i18n)
- [JavaScript](#javascript)
  - [Tree Shaking](#tree-shaking)
  - [Code Splitting](#code-splitting)
  - [JavaScript Caveats](#javascript-caveats)
- [CSS](#css)
  - [Importing CSS from JavaScript](#importing-css-from-javascript)
  - [CSS Modules](#css-modules)
  - [CSS Mixins](#css-mixins)
  - [CSS Caveats](#css-caveats)
- [Typescript](#typescript)
  - [Typescript Caveats](#typescript-caveats)
- [JSX](#jsx)
- [JSON](#json)
- [Phlex Support](#phlex-support)
- [ViewComponent Support](#viewcomponent-support)
- [Cache Busting](#cache-busting)
- [rjs is back!](#rjs-is-back)
- [Included Paths](#included-paths)
- [Thanks](#thanks)
- [Development](#development)

## Getting Started

Getting started obviously depends on whether you are adding Proscenium to an existing Rails app, or creating a new Rails app. So please choose the appropriate guide below:

- [Getting Started with a new Rails app](https://github.com/joelmoss/proscenium/blob/master/docs/guides/new_rails_app.md)
- Getting Started with an existing Rails app *[Coming soon]*
  - Upgrading from Sprockets *[Coming soon]*
  - Upgrading from Propshaft *[Coming soon]*
  - Upgrading from Webpacker *[Coming soon]*

## Installation

Add this line to your Rails application's Gemfile, and you're good to go:

```ruby
gem 'proscenium'
```

Please note that Proscenium is designed solely for use with Rails, so will not work - at least out of the box - anywhere else.

## Client-Side Code Anywhere

Proscenium believes that your frontend code is just as important as your backend code, and is not an afterthought - they should be first class citizens of your Rails app. So instead of having to throw all your JS and CSS into a "app/assets" directory, and then requiring a separate process to compile or bundle, just put them wherever you want within your app, and just run Rails!

For example, if you have some JS that is required by your `app/views/users/index.html.erb` view, just create a JS file alongside it at `app/views/users/index.js`. Or if you have some CSS that is used by your entire application, put it in `app/views/layouts/application.css` and load it alongside your layout. Maybe you have a few JS utility functions, so put them in `lib/utils.js`.

Simply put your JS(X) and CSS anywhere you want, and they will be served by your Rails app from the location where you placed them.

Using the examples above...

- `app/views/users/index.js` => `https://yourapp.com/app/views/users/index.js`
- `app/views/layouts/application.css` => `https://yourapp.com/app/views/layouts/application.css`
- `lib/utils.js` => `https://yourapp.com/lib/utils.js`
- `app/components/menu_component.jsx` => `https://yourapp.com/app/components/menu_component.jsx`
- `config/properties.css` => `https://yourapp.com/config/properties.css`

## Side Loading

> Prior to **0.10.0**, only assets with the extension `.js`, `.ts` and `.css` were side loaded. From 0.10.0, all assets are side loaded, including `.jsx`, and `.tsx`. Also partials were not side loaded prior to 0.10.0.

Proscenium is best experienced when you side load your assets.

### The Problem

With Rails you would typically declaratively load your JavaScript and CSS assets using the `javascript_include_tag` and `stylesheet_link_tag` helpers.

For example, you may have top-level "application" CSS located in a file at `/app/assets/application.css`. Likewise, you may have some global JavaScript located in a file at `/app/assets/application.js`.

You would include those two files in your application layout, something like this:

```erb
<%# /app/views/layouts/application.html.erb %>

<!DOCTYPE html>
<html>
  <head>
    <title>Hello World</title>
    <%= stylesheet_link_tag 'application' %> <!-- << Your app CSS -->
  </head>
  <body>
    <%= yield %>
    <%= javascript_include_tag 'application' %> <!-- << Your app JS -->
  </body>
</html>
```

Now, you may have some CSS and JavaScript that is only required by a specific view and partial, so you would load that in your view, something like this:

```erb
<%# /app/views/users/index.html.erb %>

<%= stylesheet_link_tag 'users' %>
<%= javascript_include_tag 'users' %>

<%# needed by the `users/_user.html.erb` partial %>
<%= javascript_include_tag '_user' %>

<% render @users %>
```

The main problem is that you have to keep track of all these assets, and make sure each is loaded by all the views that require them, but also avoid loading them when not needed. This can be a real pain, especially when you have a lot of views.

### The Solution

When side loading your JavaScript, Typescript and CSS with Proscenium, they are automatically included alongside your views, partials, layouts, and components, and only when needed.

Side loading works by looking for a JS/TS/CSS file with the same name as your view, partial, layout or component. For example, if you have a view at `app/views/users/index.html.erb`, then Proscenium will look for a JS/TS/CSS file at `app/views/users/index.js`, `app/views/users/index.ts` or `app/views/users/index.css`. If it finds one, it will include it in the HTML for that view.

JSX is also supported for JavaScript and Typescript. Simply use the `.jsx` or `.tsx` extension instead of `.js` or `.ts`.

### Usage

Simply create a JS and/or CSS file with the same name as any view, partial or layout.

Let's continue with our problem example above, where we have the following assets

- `/app/assets/application.css`
- `/app/assets/application.js`
- `/app/assets/users.css`
- `/app/assets/users.js`
- `/app/assets/user.js`

Your application layout is at `/app/views/layouts/application.hml.erb`, and the view that needs the users assets is at `/app/views/users/index.html.erb`, so move your assets JS and CSS alongside them:

- `/app/views/layouts/application.css`
- `/app/views/layouts/application.js`
- `/app/views/users/index.css`
- `/app/views/users/index.js`
- `/app/views/users/_user.js` (partial)

Now, in your layout and view, replace the `javascript_include_tag` and `stylesheet_link_tag` helpers with the `side_load_stylesheets` and `side_load_javascripts` helpers from Proscenium. Something like this:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Hello World</title>
    <%= side_load_stylesheets %>
  </head>
  <body>
    <%= yield %>
    <%= side_load_javascripts defer: true, type: 'module' %>
  </body>
</html>
```

> NOTE that Proscenium is desiged to work with modern JavaAscript, and assumes [ESModules](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Modules) are used everywhere. This is why the `type` attribute is set to `module` in the example above. If you are not using ESModules, then you can omit the `type` attribute.

On each page request, Proscenium will check if your views, layouts and partials have a JS/TS/CSS file of the same name, and then include them wherever your placed the `side_load_stylesheets` and `side_load_javascripts` helpers.

Now you never have to remember to include your assets again. Just create them alongside your views, partials and layouts, and Proscenium will take care of the rest.

Side loading is enabled by default, but you can disable it by setting `config.proscenium.side_load` to `false` in your `/config/application.rb`.

## Importing Assets

Proscenium supports importing JS, JSX, TS, TSX, CSS and SVG from NPM, by URL, your local app, and even from Ruby Gems.

Imported files are bundled together in real time. So no build step or pre-compilation is needed.

Imports are assumed to be JS files, so there is no need to specify the file extesnion in such cases. But you can if you like. All other file types must be specified using their full file name and extension.

### URL Imports

Any import beginning with `http://` or `https://` will be fetched from the URL provided. For example:

```js
import React from 'https://esm.sh/react'
```

```css
@import 'https://cdn.jsdelivr.net/npm/bootstrap@5.2.0/dist/css/bootstrap.min.css';
```

URL imports are cached, so that each import is only fetched once per server restart.

### Import from NPM (`node_modules`)

Bare imports (imports not beginning with `./`, `/`, `https://`, `http://`) are fully supported, and will use your package manager of choice (eg, NPM, Yarn, pnpm) via the `package.json` file:

```js
import React from 'react'
```

### Local Imports

And of course you can import your own code, using relative or absolute paths (file extension is optional):

```js /app/views/layouts/application.js
import utils from '/lib/utils'
```

```js /lib/utils.js
import constants from './constants'
```

## Import Maps

> **[WIP]**

[Import maps](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap) for both JS and CSS is supported out of the box, and works with no regard to the browser being used. This is because the import map is parsed and resolved by Proscenium on the server, instead of by the browser. This is faster, and also allows you to use import maps in browsers that do not support them yet.

If you are not familiar with import maps, think of them as a way to define aliases.

Just create `config/import_map.json` and specify the imports you want to use. For example:

```json
{
  "imports": {
    "react": "https://esm.sh/react@18.2.0",
    "start": "/lib/start.js",
    "common": "/lib/common.css",
    "@radix-ui/colors/": "https://esm.sh/@radix-ui/colors@0.1.8/",
  }
}
```

Using the above import map, we can do...

```js
import { useCallback } from 'react'
import startHere from 'start'
import styles from 'common'
```

and for CSS...

```css
@import 'common';
@import '@radix-ui/colors/blue.css';
```

You can also write your import map in JavaScript instead of JSON. So instead of `config/import_map.json`, create `config/import_map.js`, and define an anonymous function. This function accepts a single `environment` argument.

```js
env => ({
  imports: {
    react: env === 'development' ? 'https://esm.sh/react@18.2.0?dev' : 'https://esm.sh/react@18.2.0'
  }
})
```

## Source Maps

Source maps can make it easier to debug your code. They encode the information necessary to translate from a line/column offset in a generated output file back to a line/column offset in the corresponding original input file. This is useful if your generated code is sufficiently different from your original code (e.g. your original code is TypeScript or you enabled minification). This is also useful if you prefer looking at individual files in your browser's developer tools instead of one big bundled file.

Source map output is supported for both JavaScript and CSS. Each file is appended with the link to the source map. For example:

```js
//# sourceMappingURL=/app/views/layouts/application.js.map
```

Your browsers dev tools should pick this up and automatically load the source map when and where needed.

## SVG

You can import SVG from JS(X), which will bundle the SVG source code. Additionally, if importing from JSX or TSX, the SVG source code will be rendered as a JSX/TSX component.

## Environment Variables

> Available in `>=0.10.0`

You can defined and access any environment variable from your JavaScript and Typescript under the `proscenium.env` namespace.

For performance and security reasons you must declare the environment variable names that you wish to expose in your `config/application.rb` file.

```ruby
config.proscenium.env_vars = Set['API_KEY', 'SOME_SECRET_VARIABLE']
config.proscenium.env_vars << 'ANOTHER_API_KEY'
```

This assumes that the environment variable of the same name has already been defined. If not, you will need to define it yourself either in your code using Ruby's `ENV` object, or in your shell.

These declared environment variables will be replaced with constant expressions, allowing you to use this like this:

```js
console.log(proscenium.env.RAILS_ENV) // console.log("development")
console.log(proscenium.env.RAILS_ENV === 'development') // console.log(true)
```

The `RAILS_ENV` and `NODE_ENV` environment variables will always automatically be declared for you.

In addition to this, Proscenium also provides a `process.env.NODE_ENV` variable, which is set to the same value as `proscenium.env.RAILS_ENV`. It is provided to support the community's existing tooling, which often relies on this variable.

Environment variables are particularly powerful in aiding [tree shaking](#tree-shaking).

```js
function start() {
  console.log("start")
}
function doSomethingDangerous() {
  console.log("resetDatabase")
}

proscenium.env.RAILS_ENV === "development" && doSomethingDangerous()

start()
```

In development the above code will be transformed into the following code, discarding the definition, and call to`doSomethingDangerous()`.

```js
function start() {
  console.log("start")
}
start()
```

Please note that for security reasons environment variables are not replaced in URL imports.

An undefined environment variable will be replaced with `undefined`.

```js
console.log(proscenium.env.UNKNOWN) // console.log((void 0).UNKNOWN)
```

This means that code that relies on this will not be tree shaken. You can work around this by using the [optional chaining operator](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Optional_chaining):

```js
if (typeof proscenium.env?.UNKNOWN !== "undefined") {
  // do something if UNKNOWN is defined
}
```

## i18n

Basic support is provided for importing your Rails locale files from `config/locales/*.yml`, exporting them as JSON.

```js
import translations from '@proscenium/i18n'
// translations.en.*
```

## Javascript

By default, Proscenium's output will take advantage of all modern JS features. For example, `a !== void 0 && a !== null ? a : b` will become `a ?? b` when minifying (enabled by default in production), which makes use of syntax from the ES2020 version of JavaScript.

### Tree Shaking

Tree shaking is the term the JavaScript community uses for dead code elimination, a common compiler optimization that automatically removes unreachable code. Tree shaking is enabled by default in Proascenium.

```javascript
function one() {
  console.log('one')
}
function two() {
  console.log('two')
}
one()
```

The above code will be transformed to the following code, discarding `two()`, as it is never called.

```javascript
function one() {
  console.log("one");
}
one();
```

### Code Splitting

> Available in `>=0.10.0`

[Side loaded](#side-loading) assets are automatically code split. This means that if you have a file that is imported and used imported several times, and by different files, it will be split off into a separate file.

As an example:

```js
// /lib/son.js
import father from "./father";

father() + " and Son";
```

```js
// /lib/daughter.js
import father from "./father";

father() + " and Daughter";
```

```js
// /lib/father.js
export default () => "Father";
```

Both `son.js` and `daughter.js` import `father.js`, so both son and daughter would usually include a copy of father, resulting in duplicated code and larger bundle sizes.

If these files are side loaded, then `father.js` will be split off into a separate file or chunk, and only downloaded once.

- Code shared between multiple entry points is split off into a separate shared file that both entry points import. That way if the user first browses to one page and then to another page, they don't have to download all of the JavaScript for the second page from scratch if the shared part has already been downloaded and cached by their browser.

- Code referenced through an asynchronous `import()` expression will be split off into a separate file and only loaded when that expression is evaluated. This allows you to improve the initial download time of your app by only downloading the code you need at startup, and then lazily downloading additional code if needed later.

- Without code splitting, an import() expression becomes `Promise.resolve().then(() => require())` instead. This still preserves the asynchronous semantics of the expression but it means the imported code is included in the same bundle instead of being split off into a separate file.

You can disable code splitting by setting the `code_splitting` configuration option to `false` in your application's `/config/application.rb`:

```ruby
config.proscenium.code_splitting = false
```


### JavaScript Caveats

There are a few important caveats as far as JavaScript is concerned. These are [detailed on the esbuild site](https://esbuild.github.io/content-types/#javascript-caveats).

## CSS

CSS is a first-class content type in Proscenium, which means it can bundle CSS files directly without needing to import your CSS from JavaScript code. You can `@import` other CSS files and reference image and font files with `url()` and Proscenium will bundle everything together.

Note that by default, Proscenium's output will take advantage of all modern CSS features. For example, `color: rgba(255, 0, 0, 0.4)` will become `color: #f006` after minifying in production, which makes use of syntax from [CSS Color Module Level 4](https://drafts.csswg.org/css-color-4/#changes-from-3).

The new CSS nesting syntax is supported, and transformed into non-nested CSS for older browsers.

### Importing CSS from JavaScript

You can also import CSS from JavaScript. When you do this, Proscenium will automatically append each stylesheet to the document's head as a `<link>` element.

```jsx
import './button.css'

export let Button = ({ text }) => {
  return <div className="button">{text}</div>
}
```

### CSS Modules

Proscenium implements a subset of [CSS Modules](https://github.com/css-modules/css-modules). It supports the `:local` and `:global` keywords, but not the `composes` property. It is recommended that you use mixins instead of `composes`, as they work everywhere.

Give any CSS file a `.module.css` extension, and Proscenium will load it as a CSS Module...

```css
.header {
  background-color: #00f;
}
```

The above input produces:

```css
.header5564cdbb {
  background-color: #00f;
}
```

Importing a CSS file from JS will automatically append the stylesheet to the document's head. And the results of the import will be an object of CSS class to module names.

```js
import styles from './styles.module.css'
// styles == { header: 'header5564cdbb' }
```

It is important to note that the exported object of CSS module names is actually a Proxy object. So destructuring the object will not work. Instead, you must access the properties directly.

Also, importing a CSS module from another CSS module will result in the same digest string for all classes.

### CSS Mixins

Proscenium provides functionality for including or "mixing in" onr or more CSS classes into another. This is similar to the `composes` property of CSS Modules, but works everywhere, and is not limited to CSS Modules.

CSS mixins are supported using the `@define-mixin` and `@mixin` at-rules.

A mixin is defined using the `@define-mixin` at-rule. Pass it a name, which should adhere to class name semantics, and declare your rules:

```css
// /lib/mixins.css
@define-mixin bigText {
  font-size: 50px;
}
```

Use a mixin using the `@mixin` at-rule. Pass it the name of the mixin you want to use, and the url where the mixin is declared. The url is used to resolve the mixin, and can be relative, absolute, a URL, or even from an NPM packacge.

```css
// /app/views/layouts/application.css
p {
  @mixin bigText from url('/lib/mixins.css');
  color: red;
}
```

The above produce this output:

```css
p {
  font-size: 50px;
  color: red;
}
```

Mixins can be declared in any CSS file. They do not need to be declared in the same file as where they are used. however, if you declare and use a mixin in the same file, you don't need to specify the URL of where the mixin is declared.

```css
@define-mixin bigText {
  font-size: 50px;
}

p {
  @mixin bigText;
  color: red;
}
```

CSS modules and Mixins works perfectly together. You can include a mixin in a CSS module.

### CSS Caveats

There are a few important caveats as far as CSS is concerned. These are [detailed on the esbuild site](https://esbuild.github.io/content-types/#css-caveats).

## Typescript

Typescript and TSX is supported out of the box, and has built-in support for parsing TypeScript syntax and discarding the type annotations. Just rename your files to `.ts` or `.tsx` and you're good to go.

Please note that Proscenium does not do any type checking so you will still need to run `tsc -noEmit` in parallel with Proscenium to check types.

### Typescript Caveats

There are a few important caveats as far as Typescript is concerned. These are [detailed on the esbuild site](https://esbuild.github.io/content-types/#typescript-caveats).

## JSX

Using JSX syntax usually requires you to manually import the JSX library you are using. For example, if you are using React, by default you will need to import React into each JSX file like this:

```javascript
import * as React from 'react'
render(<div/>)
```

This is because the JSX transform turns JSX syntax into a call to `React.createElement` but it does not itself import anything, so the React variable is not automatically present.

Proscenium generates these import statements for you. Keep in mind that this also completely changes how the JSX transform works, so it may break your code if you are using a JSX library that is not React.

In the [not too distant] future, you will be able to configure Proscenium to use a different JSX library, or to disable this auto-import completely.

## JSON

Importing .json files parses the JSON file into a JavaScript object, and exports the object as the default export. Using it looks something like this:

```javascript
import object from './example.json'
console.log(object)
```

In addition to the default export, there are also named exports for each top-level property in the JSON object. Importing a named export directly means Proscenium can automatically remove unused parts of the JSON file from the bundle, leaving only the named exports that you actually used. For example, this code will only include the version field when bundled:

```javascript
import { version } from './package.json'
console.log(version)
```

## Phlex Support

> *docs needed*

## ViewComponent Support

> *docs needed*

## Cache Busting

> *COMING SOON*

By default, all assets are not cached by the browser. But if in production, you populate the `REVISION` env variable, all CSS and JS URL's will be appended with its value as a query string, and the `Cache-Control` response header will be set to `public` and a max-age of 30 days.

For example, if you set `REVISION=v1`, URL's will be appended with `?v1`: `/my/imported/file.js?v1`.

It is assumed that the `REVISION` env var will be unique between deploys. If it isn't, then assets will continue to be cached as the same version between deploys. I recommend you assign a version number or to use the Git commit hash of the deploy. Just make sure it is unique for each deploy.

You can set the `cache_query_string` config option directly to define any query string you wish:

```ruby
Rails.application.config.proscenium.cache_query_string = 'my-cache-busting-version-string'
```

The cache is set with a `max-age` of 30 days. You can customise this with the `cache_max_age` config option:

```ruby
Rails.application.config.proscenium.cache_max_age = 12.months.to_i
```

## rjs is back!

Proscenium brings back RJS! Any path ending in .rjs will be served from your Rails app. This allows you to import server rendered javascript.

## Serving from Ruby Gem

*docs needed*

## Included Paths

By default, Proscenium will serve files ending with any of these extension: `js,mjs,ts,css,jsx,tsx`, and only from `app/assets`, `config`, `app/views`, `lib` and `node_modules` directories.

However, you can customise these paths with the `include_path` config option...

```ruby
Rails.application.config.proscenium.include_paths << 'app/components'
```

## Thanks

HUGE thanks 🙏 go to [Evan Wallace](https://github.com/evanw) and his amazing [esbuild](https://esbuild.github.io/) project. Proscenium would not be possible without it, and it is esbuild that makes this so fast and efficient.

Because Proscenium uses esbuild extensively, some of these docs are taken directly from the esbuild docs, with links back to the [esbuild site](https://esbuild.github.io/) where appropriate.

## Development

Before doing anything else, you will need compile a local version of the Go binary. This is because the Go binary is not checked into the repo. To compile the binary, run:

```bash
bundle exec rake compile:local
```

### Running tests

We have tests for both Ruby and Go. To run the Ruby tests:

```bash
bundle exec rake test
```

To run the Go tests:

```bash
go test ./test
```

### Running Go benchmarks

```bash
go test ./internal/builder -bench=. -run="^$" -count=10 -benchmem
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joelmoss/proscenium. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Proscenium project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).
