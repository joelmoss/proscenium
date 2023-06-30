# Getting Started with an Existing Rails app

Here we will guide you through the process of adding *Proscenium* to an existing Rails 7 app, and demonstrate how simple and easy it is to use, especially when you [side load](/README.md#side-loading) your client side code.

## Prerequisites

There is absolutely nothing else that you need to install or configure to get started with *Proscenium*. It is a Ruby gem, and it will work with any version of Rails 7 or higher.

## Migrate from Sprockets

1. Replace `sprockets-rails` with `proscenium` in your Gemfile.
2. Remove all `config.assets.*` settings from your `config/environments/*` files.
3. Delete `app/assets/config/manifest.js`.
4. Delete the `config/initializers/assets.rb` file.
5. Replace all asset_helpers (`image_url`, `font_url`) in css files with standard `url()`s.
6. If you are importing only the frameworks you need (instead of `rails/all`), remove `require "sprockets/railtie"` from your `config/application.rb` file.
7. Update calls to `stylesheet_link_tag` and `javascript_include_tag` with full paths to your CSS and JS assets.
8. Remove all sprockets directives, and replace with import statements.

### Asset helpers

Proscenium does not rely on asset_helpers (`asset_path`, `asset_url`, `image_url`, etc.) like Sprockets did. Instead, you simply use the standard `url()` function in your css files, and use absolute or relative URL's.

```diff
- background: image_url('hero.jpg');
+ background: url('/hero.jpg');
```

### Asset paths

Sprockets required all your assets be loacted in the `app/assets` directory, and calls to the `stylesheet_link_tag` and `javascript_include_tag` helpers would automatically prepend the `app/assets` path to the asset name. Proscenium does not do this, because assets can be located anywhere. So you must provide the absolute path to your assets.

```diff
- <%= stylesheet_link_tag "application" %>
+ <%= stylesheet_link_tag "/app/assets/stylesheets/application" %>
```

### Sprockets directives

If you are using sprockets directives such as `//= require jquery`, `//= require_tree .`, etc., you will need to replace these with standard [`import` statements](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/import) in JavaScript, and [`@import` at-rules](https://developer.mozilla.org/en-US/docs/Web/CSS/@import) in your CSS.

```diff
- //= require jquery
+ import 'jquery'
```

```diff
- /* require bootstrap */
+ @import url('bootstrap')
```

## Next Steps

The recommended next step is to [side load](/README.md#side-loading) your JS and CSS assets.
