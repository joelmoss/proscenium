# Proscenium

- Serve assets from anywhere within your Rails root.
- Automatically side load JS/CSS for your layouts and views.
- Import JS and CSS from node_modules, URL, local (relative, absolute)
- Real-time bundling of JS, JSX and CSS.
- Import Map
- CSS Modules
- Minification

## Installation

Add this line to your application's Gemfile, and you're good to go:

```ruby
gem 'proscenium'
```

## Frontend Code Anywhere!

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
import doStuff from 'stuff?bundle'
doStuff()
```

Bundling a URL import is not supported, as the URL itself may also support query parameters,
resulting in conflicts. For example, esm.sh also supports a `?bundle` param, bundling a module's
dependencies into a single file. Instead, you should install the module locally using your favourite
package manager.

## Import Map

Import map for both JS and CSS is supported out of the box, and works with no regard to the browser
version being used. Just create `config/import_map.json`:

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

Direct access to CSS files are parsed through @parcel/css.

Importing a CSS file from JS will append the CSS file to the document's head. The results of the
import will be an object of CSS modules.

## Auto Reload

To aid fast development, Proscenium comes with an auto reload feature that will automatically reload
the page when any files changes. It is enabled by default in development, and requires that you
mount the Proscenium Railtie into your `config/routes.rb` file:

```ruby
mount Proscenium::Railtie, at: '/proscenium' if Rails.env.development?
```

Changes to CSS/JS(X) files in your `app` and `lib` directories will cause the page to reload.

NOTE: that this is hot module reloading (HMR) - a full page reload is triggered.

You can disable auto reload by setting the `config.proscenium.auto_reload` config option to false.

## CSS Custom Media Queries

Proscenium supports [custom media queries](https://css-tricks.com/can-we-have-custom-media-queries-please/) as per the [spec](https://www.w3.org/TR/mediaqueries-5/#custom-mq). However, because of the way they are parsed, they cannot be imported using `@import`. So if you define your custom media queries in `/config/custom_media_queries.css`, Proscenium will automatically inject them into your CSS, so you can use them anywhere.

## How It Works

Proscenium provides a Rails middleware that proxies requests for your frontend code. By default, it will simply search for a file of the same name in your Rails root. For example, a request for '/app/views/layouts/application.js' or '/lib/hooks.js' will return that exact file relative to your Rails root.

This allows your frontend code to become first class citizens of you Rails application.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Compile the compilers

`deno compile --no-config -o bin/compilers/esbuild --import-map import_map.json -A lib/proscenium/compilers/esbuild.js`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joelmoss/proscenium. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Proscenium project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).
