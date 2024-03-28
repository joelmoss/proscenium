# frozen_string_literal: true

class ViewComponent::CssModule::Component < Proscenium::ViewComponent
  def call
    tag.h1('Hello', class: %i[foo @hello]) + tag.h2('World', class: '@world')
  end
end
