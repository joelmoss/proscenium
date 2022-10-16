class ViewComponent::CssModule::Component < ApplicationComponent
  def initialize(class_name:)
    @class_name = class_name
  end

  def call
    tag.h1 'Hello', class: @class_name
  end
end
