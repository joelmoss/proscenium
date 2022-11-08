# frozen_string_literal: true

class ViewComponent::CssModule::Component < Proscenium::ViewComponent
  def initialize(class_name:) # rubocop:disable Lint/MissingSuper:
    @class_name = class_name
  end

  def call
    tag.h1 'Hello', class: @class_name
  end
end
