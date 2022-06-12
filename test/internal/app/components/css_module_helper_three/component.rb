class CssModuleHelperThree::Component < ApplicationComponent
  def call
    tag.h1 'Hello', css_module: :header
  end
end
