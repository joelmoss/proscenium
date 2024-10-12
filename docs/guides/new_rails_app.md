# Getting Started with a new Rails app

Here we will guide you through the process of setting up a new Rails app with _Proscenium_, and demonstrate how simple and easy it is to use, especially when you [side load](/README.md#side-loading) your client side code. It's also a great starting point if you just use JavaScript sprinkles.

## Prerequisites

Apart from the usual Rails prerequisites, there is absolutely nothing else that you need to install or configure to get started with _Proscenium_. It is a Ruby gem, and it will work with any version of Rails 7 or higher.

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

We need some code to play with, so lets create a new model, controller and view using the Rails scaffold generator. Run the following command to scaffold an Article resource:

```bash
rails g scaffold article title
```

And finally start the Rails server:

```bash
rails server
```

Now open up your app in your browser at http://localhost:3000/articles, and you should see the scaffolded views for your Article resource.

Let's add a little styling to our app. Open up `app/assets/stylesheets/application.css`, and replace its contenets with the following:

```css
body {
  font-family: sans-serif;

  h1 {
    color: red;
  }
}
```

Reload http://localhost:3000/articles and you will see your styling applied to the page!

Note that we used CSS nesting above, which is a new CSS syntax that only supported by the most recent browser versions. Proscenium will automatically transform this to standard CSS that is supported by older browsers, and it will do so in real time. You can see this by going to http://localhost:3000/app/assets/stylesheets/application.css in your browser. It should look like this:

```css
/* app/assets/stylesheets/application.css */
body {
  font-family: sans-serif;
}
body h1 {
  color: red;
}
/*# sourceMappingURL=application.css.map */
```

Now lets add some JavaScript sprinkles to our app. Create a new file (or replace the existing one) at `app/javascript/application.js` with the following contents:

```js
import confetti from "https://esm.sh/canvas-confetti@1.6.0";
confetti();
```

Then include that JS file using Rails `javascript_include_tag` helper. Add the following line to your `app/views/layouts/application.html.erb` file, just before the closing `</body>` tag:

```erb
<%= javascript_include_tag "application", type: 'module' %>
```

Now open up your app in your browser at http://localhost:3000/articles, and you should see some confetti!

## Automatically Including your JavaScript and CSS

Even though you created a Rails app without the default asset pipeline provided by Rails, Rails still assumes that you will be serving your CSS from the `app/assets/stylesheets` directory, and your JS from the `app/javascript` directory. Proscenium makes no such assumption, and you can [serve your assets from anywhere you like](https://github.com/joelmoss/proscenium#client-side-code-anywhere).

While you could of course use the `javascript_include_tag` and `stylesheet_link_tag` helpers to [manually include](#manually-including-your-javascript-and-css) your JavaScript and CSS, Proscenium provides a much better way to do this by side loading your client side code.

[Side loading](/README.md#side-loading) is the process of automatically including your client side code alongside your Rails views. Let's see how this works:

Your new Rails app already has a `app/views/layouts/application.html.erb` file, which is the default layout for your app. Open it up and look for the `stylesheet_link_tag` and `javascript_include_tag` helpers. You need to replace these helpers with the `include_stylesheets` and `include_javascripts` helpers provided by Proscenium, ending up with something like this:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>Vanilla</title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= include_stylesheets %> # <--
  </head>

  <body>
    <%= yield %>

    <%= include_javascripts %> # <--
  </body>
</html>
```

You may have noticed that unlike the original Rails helpers that you just replaced, the `include_stylesheets` and `include_javascripts` helpers do not require that you specify the name of the file(s) to include - Proscenium will figure that out for you.

### Side load your application layout

Earlier we added some JS into `app/javascript/application.js`. Let's move that to `app/views/layouts/application.js` so it is alongside your application layout at `app/views/layouts/application.html.erb`.

Then do the same with the application CSS, moving that from `app/assets/stylesheets/application.css` to `app/views/layouts/application.css`.

Now open up your browser at http://localhost:3000/articles, and reload. You should still see the same styling and confetti!

### Side load your views

We now want to add some different styling to the articles index page, while still keeping all other pages the same; using the application CSS.

Create a new file alongside the articles index view at `app/views/views/articles/index.css` with the following contents:

```css
body {
  background-color: black;
  color: red;
}
```

Now reload the page at [http://localhost:3000/articles], and you should see that the background is now black, and the text is red.

Click the "New article" link, and you should see that the background is now white, and the text is black. This is because the `app/views/views/articles/new.html.erb` view that is currently rendered has no files to side load. However, you will still see the confetti appear because your application layoput is still side loaded.

## Manually Including your JavaScript and CSS

Proscenium still suppports the `stylesheet_link_tag` and `javascript_include_tag` helpers provided by Rails, so you can still use these if you prefer. Let's see how this works:

For simplicities sake, lets use `app/assets` for now, because Rails has already set up an `app/assets/stylesheets` directory for us, with an `application.css` file.

Rails also still assumes that your assets are aliased, and will be accessible from the root of your domain. Meaning `/app/assets/stylesheets/application.css` will be accessible at `https://example.com/assets/application.css`. Proscenium uses the full path as the URL, so `/app/assets/stylesheets/application.css` will be accessible at `https://example.com/app/assets/stylesheets/application.css`.

Just gotta do one thing to make this work. Open up `app/views/layouts/application.html.erb` and change the path argument provided to the `stylesheet_link_tag` helper from `application` to the full path of the file `/app/assets/stylesheets/application`.

```erb
<%= stylesheet_link_tag "application" %>
```

to this:

```erb
<%= stylesheet_link_tag "/app/assets/stylesheets/application" %>
```

## In Conclusion

What you now have is the powerful ability to serve your client side code from anywhere in your Rails app, along with minified, tree-shaken and source-mapped code, support for import maps, and importing from NPM, and [so much more](https://github.com/joelmoss/proscenium).
