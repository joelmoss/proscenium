# frozen_string_literal: true

class DryInitializerAppComponent < Proscenium::ViewComponent
  self.abstract_class = true
  extend Dry::Initializer
end

class ViewComponent::DryInitializerComponent < DryInitializerAppComponent
  def call
    tag.h1 'Hello', class: :base
  end
end
