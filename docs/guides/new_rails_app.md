# Getting Started with a new Rails app

Here we will guide you through the process of setting up a new Rails app with *Proscenium*, and demonstrate how simple and easy it is to get going. It's also a great starting point if you just use JavaScript sprinkles.

## Prerequisites

Apart from the usual Rails prerequisites, there is absolutely nothing else that you need to install or configure to get started with *Proscenium*. It is a Ruby gem, and it will work with any version of Rails 7 or higher.

## Creating a new Rails app

By default, the `rails new` command installs and sets up a whole bunch of things that you no longer need at all when using Proscenium.

To create a new Rails app, simply run the following command, replacing `my_app` with the name of your app:

```bash
rails new my_app --skip-asset-pipeline --skip-javascript
```

Now open up your new app in your favourite code editor or IDE, and add the following line to your `Gemfile`:

```ruby
gem 'proscenium'
```

Now run `bundle install` to install the gem and update your bundle.

## Serving Your First Asset

Even though you created a Rails app without the default asset pipeline provided by Rails, Rails still assumes that you will be serving your JavaScript and CSS from the `app/assets` directory. Proscenium makes no such assumption, and you can [serve your assets from anywhere you like](https://github.com/joelmoss/proscenium#client-side-code-anywhere).

But for simplicities sake, lets use `app/assets` for now, because Rails has already set up an `app/assets/stylesheets` directory for us, with an `application.css` file.

Rails also still assumes that your assets are aliased, and will be accessible from the root of your domain. Meaning `/app/assets/stylesheets/application.css` will be accessible at `https://example.com/assets/application.css`. Proscenium uses the full path as the URL, so `/app/assets/stylesheets/application.css` will be accessible at `https://example.com/app/assets/stylesheets/application.css`.

Just gotta do one thing to make this work. Open up `app/views/layouts/application.html.erb` and change the argument provided to the `stylesheet_link_tag` helper from this:

```erb
<%= stylesheet_link_tag "application" %>
```

to this:

```erb
<%= stylesheet_link_tag "/app/assets/stylesheets/application" %>
```

## Adding some JavaScript

Now lets add some JavaScript. Add this line to the bottom of your `app/views/layouts/application.html.erb` file, just above the closing body tag:

```erb
<%= javascript_include_tag "app/assets/javascripts/application", type: 'module', defer: true %>
```

Create a new file at `app/assets/javascripts/application.js` and add some JS:

```js
import confetti from "https://esm.sh/canvas-confetti@1.6.0";
confetti();
```

## In Conclusion

What you now have is the powerful ability to serve your client side code from anywhere in your Rails app, along with minified, tree-shaken and source-mapped code, support for import maps, and importing from NPM, and [so much more](https://github.com/joelmoss/proscenium).
