class ViewComponent::CssModuleHelperTwoComponent < ApplicationComponent
  def call
    tag.h1 'Hello', class: css_module(:header)
  end
end
