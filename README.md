# Proscenium - Modern Client-Side Tooling for Rails

Proscenium treats your client-side code as first class citizens of your Rails app, and assumes a
"fast by default" internet. It compiles your JS, JSX and CSS in real time, and on demand, with no
configuration at all!

- Zero configuration.
- NO JavaScript rumtime needed - just the browser!
- Real-time compilation.
- No additional process or server - Just run Rails!
- Serve assets from anywhere within your Rails root (/app, /config, /lib).
- Automatically side load JS/CSS for your layouts and views.
- Import JS(X) and CSS from node_modules, URL, local (relative, absolute).
- Optional bundling of JS(X) and CSS.
- Import Map support for JS and CSS.
- CSS Modules.
- CSS Custom Media Queries.
- CSS mixins.
- Minification.

## ⚠️ EXPERIMENTAL SOFTWARE ⚠️

While my goal is to use Proscenium in production, I strongly recommended that you **DO NOT** use
this in production apps! Right now, this is a play thing, and should only be used for
development/testing.

## Installation

Add this line to your application's Gemfile, and you're good to go:

```ruby
gem 'proscenium'
```

## Frontend Code Anywhere

Proscenium believes that your frontend code is just as important as your backend code, and is not an
afterthought - they should be first class citizens of your Rails app. So instead of throwing all
your JS and CSS into a "app/assets" directory, put them wherever you want!

For example, if you have JS that is used by your `UsersController#index`, then put it in
`app/views/users/index.js`. Or if you have some CSS that is used by your entire application, put it
in `app/views/layouts/application.css`. Maybe you have a few JS utility functions, so put them in
`lib/utils.js`.

Simply create your JS(X) and CSS anywhere you want, and they will be served by your Rails app.

Using the examples above...

- `app/views/users/index.js` => `https://yourapp.com/app/views/users/index.js`
- `app/views/layouts/application.css` => `https://yourapp.com/app/views/layouts/application.css`
- `lib/utils.js` => `https://yourapp.com/lib/utils.js`
- `config/properties.css` => `https://yourapp.com/config/properties.css`

## Importing

Proscenium supports importing JS and CSS from `node_modules`, URL, and local (relative, absolute).

Imports are assumed to be JS files, so there is no need to specify the file extesnion in such cases.
But you can if you like. All other file types must be specified using their full file name and
extension.

### URL Imports

Any import beginning with `http://` or `https://` will be fetched from the URL provided:

```js
import React from 'https://esm.sh/react`
```

```css
@import 'https://cdn.jsdelivr.net/npm/bootstrap@5.2.0/dist/css/bootstrap.min.css';
```

### Import from NPM (`node_modules`)

Bare imports (imports not beginning with `./`, `/`, `https://`, `http://`) are fully supported, and
will use your package manager of choice (eg, NPM, Yarn, pnpm):

```js
import React from 'react`
```

### Local Imports

And of course you can import your own code, using relative or absolute paths (file extension is
optional):

```js /app/views/layouts/application.js
import utils from '/lib/utils'
```

```js /lib/utils.js
import constants from './constants'
```

## Bundling

Proscenium does not do any bundling, as we believe that **the web is now fast by default**. So we
let you decide if and when to bundle your code using query parameters in your JS and CSS imports.

```js
import doStuff from 'bundle:stuff'
doStuff()
```

Note that `bundle:*` will only bundle that exact path. It will not bundle any descendant imports.
You can bundle all imports within a file by using the `bundle-all:` prefix. Use this with caution,
as you could end up swallowing everything, resulting in a very large file.

## Import Map

Import map for both JS and CSS is supported out of the box, and works with no regard to the browser
version being used. This is because the import map is parsed and resolved by Proscenium on the
server.

Just create `config/import_map.json`:

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

You can instead write your import map in Javascript instead of JSON. So instead of
`config/import_map.json`, create `config/import_map.js`, and define an anonymous function. This
function accepts a single `environment` argument.

```js
env => ({
  imports: {
    react: env === 'development' ? 'https://esm.sh/react@18.2.0?dev' : 'https://esm.sh/react@18.2.0'
  }
})
```

### Aliasing

You can also use the import map to define aliases:

```json
{
  "imports": {
    "react": "preact/compact",
  }
}
```

## Side Loading

Proscenium has built in support for automatically side loading JS and CSS with your views and
layouts.

Just create a JS and/or CSS file with the same name as any view or layout, and make sure your
layouts include `<%= side_load_stylesheets %>` and `<%= side_load_javascripts %>`. Something like
this:

```html
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

On each page request, Proscenium will check if your layout and view has a JS/CSS file of the same
name, and include them into your layout HTML. Partials are not side loaded.

Side loading is enabled by default, but you can disable it by setting `config.proscenium.side_load`
to `false`.

## CSS Modules

Give any CSS file a `.module.css` extension, and Proscenium will load it as a CSS Module...

```css
.header {
  background-color: #00f;
}
```

The above produces:

```css
.header5564cdbb {
  background-color: #00f;
}
```

Importing a CSS file from JS will automatically append the stylesheet to the document's head. The
results of the import will be an object of CSS modules.

```js
import styles from './styles.module.css'
```

## CSS Custom Media Queries

Proscenium supports [custom media queries](https://css-tricks.com/can-we-have-custom-media-queries-please/) as per the [spec](https://www.w3.org/TR/mediaqueries-5/#custom-mq). However, because of the way they are parsed, they cannot be imported using `@import`. So if you define your custom media queries in `/config/custom_media_queries.css`, Proscenium will automatically inject them into your CSS, so you can use them anywhere.

## CSS Mixins

CSS mixins are supported using the `@mixin` at-rule. Simply define your mixins in `<root>/lib` in one or more files ending in `.mixin.css`, and using the `@define-mixin` at-rule...

```css
// /lib/text.mixin.css
@define-mixin bigText {
  font-size: 50px;
}
```

```css
// /app/views/layouts/application.css
p {
  @mixin bigText;
  color: red;
}
```

## Cache Busting

By default, all assets are not cached by the browser. But if in production, you populate the
`REVISION` env variable, all CSS and JS URL's will be appended with its value as a query string, and
the `Cache-Control` response header will be set to `public` and a max-age of 30 days.

For example, if you set `REVISION=v1`, URL's will be appended with `?v1`: `/my/imported/file.js?v1`.

It is assumed that the `REVISION` env var will be unique between deploys. If it isn't, then assets
will continue to be cached as the same version between deploys. I recommend you assign a version
number or to use the Git commit hash of the deploy. Just make sure it is unique for each deploy.

You can set the `cache_query_string` config option directly to define any query string you wish:

```ruby
Rails.application.config.proscenium.cache_query_string = 'my-cache-busting-version-string'
```

The cache is set with a `max-age` of 30 days. You can customise this with the `cache_max_age` config
option:

```ruby
Rails.application.config.proscenium.cache_max_age = 12.months.to_i
```

## Include Paths

By default, Proscenium will serve files ending with any of these extension: `js,mjs,css,jsx`, and only from `config`, `app/views`, `lib` and `node_modules`.

You can customise these paths with the `include_path` config option...

```ruby
Rails.application.config.proscenium.include_paths << 'app/components'
```

## rjs is back!

Proscenium brings back rjs! Any path ending in .rjs will be served from your Rails app. This allows you to render dynamic server rendered JS.

## How It Works

Proscenium provides a Rails middleware that proxies requests for your frontend code. By default, it will simply search for a file of the same name in your Rails root. For example, a request for '/app/views/layouts/application.js' or '/lib/hooks.js' will return that exact file relative to your Rails root.

This allows your frontend code to become first class citizens of you Rails application.

The logic of how assets are handled is as follows:

- **fonts** (`.woff`, `.woff2`) are externalized.
- **SVG** (`.svg`)
  - When imported from JSX (`.jsx`):
    - It is bundled and its contents rendered as a JSX component.
  - Else is not bundled.
- **URL's**'s are encoded as a local URL path, and externalized.
- **Encoded URL's** are decoded, downloaded, cached

### Serving Assets by URL

Proscenium's primary function is a Rails middleware that intercepts URL's beginning with
`/proscenium`, and ending with any one of the supported file extensions (.js, .css, .jsx).

#### Serving from local project

`/[path]`

The `path` should map to a path in your Rails project, starting at the root (`Rails.root`).

For example, the URL `/app/views/layouts/application.js` will serve the file at
`[Rails.root]/app/views/layouts/application.js`.

#### Serving from NPM package

`/proscenium/npm:[path]`

If you have a package.json in your project, which includes dependencies, you can also serve these
with Proscenium.

For example, the URL `/proscenium/npm:react` will use your package dependencies to resolve `react`.

#### Serving from Ruby Gem

`/proscenium/gem:[path]`

Serving assets from a Ruby Gem is also possible. However, any NPM dependencies will fail to resolve.
This is because your package manager will not be aware of them. If your Gem has dependencies from
NPM, then you should publish it as a package on NPM, and require it in your project.

For example, the URL `/proscenium/gem:my_gem/lib/stuff.css` will serve the file at
`[GEMS_PATH]/my_gem/lib/stuff.css`.

#### Serving from a URL

`/proscenium/url:[ENCODED_URL]`

You can serve assets from any URL, such as a CDN. Simply use encode the URL.

For example, to serve the canvas-confetti package from `https://esm.sh/canvas-confetti@1.6.0`,
simply encode it, and append to `/proscenium/url:`. It will like
`/proscenium/url:https%3A%2F%2Fesm.sh%2Fcanvas-confetti%401.6.0`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joelmoss/proscenium. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Proscenium project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).
