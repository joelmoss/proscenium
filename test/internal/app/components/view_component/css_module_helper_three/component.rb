# frozen_string_literal: true

class ViewComponent::CssModuleHelperThree::Component < Proscenium::ViewComponent
  def call
    tag.h1 'Hello', css_module: :header
  end
end
