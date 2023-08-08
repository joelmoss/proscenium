# frozen_string_literal: true

module Proscenium
  # CSS Modules in ViewComponents can be used with the `css_module` and `css_module!` helpers, or
  # via the preferred way of passing a `@class` name. The rendered output of the component will be
  # parsed for CSS module names, and replaced with the transformed CSS module name.
  #
  # ## `css_module` and `css_module!` helpers
  #
  # The `css_module` helper will replace the class name with the CSS module name. Give it one or
  # more CSS module names, and it will return the transformed name for use as a CSS class. The
  # `css_module!` helper will raise an exception if the stylesheet is not found.
  #
  #   tag.div 'Hello World!', class: css_module(:title)
  #   # => <div class="title42099b4a">Hello World!</div>
  #
  # ## `@class` module name
  #
  # Proscenium provides a convenient convention for using CSS modules in HTML without needing to
  # call the `css_module` helper. Simply pass your CSS module names to the `class` attribute of any
  # HTML element where each name is prefixed with `@`. Proscenium will automatically replace them
  # with the transformed CSS module name.
  #
  #   tag.div 'Hello World!', class: :@title
  #   # => <div class="title42099b4a">Hello World!</div>
  #
  # Both solutions will work with the `class` attribute passed to Rails `tag` and `content_tag`
  # helpers, as well as with plain HTML/ERB.
  #
  #   <div class="@title">Hello World</div>
  #
  module ViewComponent::CssModules
    include Proscenium::CssModule

    # Transforms class names to css modules in rendered output.
    # @see Proscenium::CssModule::Resolver#transform_class_names!
    def render_in(...)
      cssm.transform_content! super(...)
    end

    private

    # Overrides ActionView::Helpers::TagHelper::TagBuilder, allowing us to intercept the
    # `css_module` option from the HTML options argument of the `tag` and `content_tag` helpers, and
    # prepend it to the HTML `class` attribute.
    def tag_builder
      @tag_builder ||= Proscenium::ViewComponent::TagBuilder.new(self)
    end
  end
end
