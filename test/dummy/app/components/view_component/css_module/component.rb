# frozen_string_literal: true

class ViewComponent::CssModule::Component < Proscenium::ViewComponent
  def call
    tag.h1 'Hello', class: :@base
  end
end
