# frozen_string_literal: true

class ViewComponent::CssModuleHelperComponent < Proscenium::ViewComponent
  def call
    tag.h1 'Hello', class: css_module(:header)
  end
end
