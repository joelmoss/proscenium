# Proscenium - Modern client-side development for Rails

Proscenium treats your client-side code as first class citizens of your Rails app, and assumes a
"fast by default" internet. It bundles your JS, JSX and CSS in real time, on demand, and with zero
configuration.

- Fast real-time bundling, tree-shaking and minification.
- Real time bundling of Javascript (.js,.jsx), Typescript (.ts,.tsx) and CSS (.css).
- NO JavaScript runtime - just the browser!
- NO build step or pre-compilation.
- NO additional process or server - Just run Rails!
- Deep integration with Rails.
- Zero configuration.
- Serve assets from anywhere within your Rails root (/app, /config, /lib, etc.).
- Automatically side load JS/TS/CSS for your layouts and views.
- Import from NPM, URLs, and locally.
- Server-side import map support.
- CSS Modules.
- CSS mixins.
- Source maps.
- Phlex and ViewComponent integration.

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

## Importing

Proscenium supports importing JS, JSX, TS and CSS from NPM, by URL, your local app, and even from Ruby Gems.

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

## Import Map [WIP]

[Import map](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/script/type/importmap) for both JS and CSS is supported out of the box, and works with no regard to the browser being used. This is because the import map is parsed and resolved by Proscenium on the server. If you are not familiar with import maps, think of it as a way to define aliases.

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

You can also write your import map in Javascript instead of JSON. So instead of `config/import_map.json`, create `config/import_map.js`, and define an anonymous function. This function accepts a single `environment` argument.

```js
env => ({
  imports: {
    react: env === 'development' ? 'https://esm.sh/react@18.2.0?dev' : 'https://esm.sh/react@18.2.0'
  }
})
```

## Side Loading

Proscenium has built in support for automatically side loading JS, TS and CSS with your views and
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

On each page request, Proscenium will check if your layout and view has a JS/TS/CSS file of the same
name, and include them into your layout HTML. Partials are not side loaded.

Side loading is enabled by default, but you can disable it by setting `config.proscenium.side_load`
to `false`.

## CSS Modules

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

## CSS Mixins

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

## Importing SVG from JS(X)

Importing SVG from JS(X) will bundle the SVG source code. Additionally, if importing from JSX, the SVG source code will be rendered as a JSX component.

## Environment Variables

Import any environment variables into your JS(X) code.

```js
import RAILS_ENV from '@proscenium/env/RAILS_ENV'
```

You can only access environment variables that are explicitly named. It will export `undefined` if the env variable does not exist.

## Importing i18n

Basic support is provided for importing your Rails locale files from `config/locales/*.yml`, exporting them as JSON.

```js
import translations from '@proscenium/i18n'
// translations.en.*
```

## Phlex Support

*docs needed*

## ViewComponent Support

*docs needed*

## Cache Busting [*COMING SOON*]

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

## Include Paths

By default, Proscenium will serve files ending with any of these extension: `js,mjs,css,jsx`, and only from `config`, `app/views`, `lib` and `node_modules` directories.

However, you can customise these paths with the `include_path` config option...

```ruby
Rails.application.config.proscenium.include_paths << 'app/components'
```

## rjs is back!

Proscenium brings back RJS! Any path ending in .rjs will be served from your Rails app. This allows you to import server rendered javascript.

## Serving from Ruby Gem

*docs needed*

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
