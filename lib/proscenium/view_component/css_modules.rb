# frozen_string_literal: true

module Proscenium
  # CSS Modules in ViewComponents can be used with the `css_module` and `css_module!` helpers.
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
  # This will also work with the `class` attribute passed to Rails `tag` and `content_tag` helpers,
  # as well as with plain HTML/ERB.
  #
  #   tag.div 'Hello World!', css_module: :title
  #   # => <div class="title42099b4a">Hello World!</div>
  #
  module ViewComponent::CssModules
    include Proscenium::CssModule

    private

    # Overrides ActionView::Helpers::TagHelper::TagBuilder, allowing us to intercept the
    # `css_module` option from the HTML options argument of the `tag` and `content_tag` helpers, and
    # prepend it to the HTML `class` attribute.
    def tag_builder
      @tag_builder ||= Proscenium::ViewComponent::TagBuilder.new(self)
    end
  end
end
