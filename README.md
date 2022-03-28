# Proscenium

- Serve assets from anywhere within the Rails root. (eg. `/app/views/layouts/application.css`, `/lib/utils/time.js`)
- Side loaded JS/CSS for your layouts and views.
- JS imports
- Dynamic imports
- Real-time bundling of JS, JSX and CSS.
- Import CSS and other static assets (images, fonts, etc.)

## WANT

- Nested CSS
- Import CSS Modules

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'proscenium'
```

## Usage

### Side Loading

Proscenium has built in support for automatically side loading JS and CSS with your views and layouts.

Just create a JS and/or CSS file with the same name as any view or layout, and make sure your layouts include `<%= yield :side_loaded_js %>` and `<%= yield :side_loaded_css %>`. Something like this:

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Hello World</title>
    <%= yield :side_loaded_css %>
  </head>
  <body>
    <%= yield %> <%= yield :side_loaded_js %>
  </body>
</html>
```

On each page request, Proscenium will check if your layout and view has a JS/CSS file of the same name, and include them into your layout HTML.

### Importing in JS with `import`

Imports that do not begin with a `./` or `/` are bare imports, and will import a package using your local Node resolution algorithm.

`import 'react'`
`import React as * from 'react'`
`import { useState } from 'react'`

Absolute and relative import paths are supported (`/*`, `./*`), and will behave as you would expect.

Imports are assumed to be JS files, so there is no need to specify the file extesnion in such cases. But you can if you like. All other file types must be specified using their fill file name and extension.

### CSS

Direct access to CSS files are parsed through @parcel/css.

Importing a CSS file from JS will append the CSS file to the document's head. The results of the import will be an object of CSS modules.

## How It Works

Proscenium provides a Rails middleware that proxies requests for your frontend code. By default, it will simply search for a file of the same name in your Rails root. For example, a request for '/app/views/layouts/application.js' or '/lib/hooks.js' will return that exact file relative to your Rails root.

This allows your frontend code to become first class citizens of you Rails application.

## Middleware/Plugins ?

```ruby
Proscenium.config.middleware << :jsx
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joelmoss/proscenium. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Proscenium project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/joelmoss/proscenium/blob/master/CODE_OF_CONDUCT.md).
