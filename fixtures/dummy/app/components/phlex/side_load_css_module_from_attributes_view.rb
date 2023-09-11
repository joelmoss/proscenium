# frozen_string_literal: true

class Phlex::SideLoadCssModuleFromAttributesView < Proscenium::Phlex
  def initialize(class_name) # rubocop:disable Lint/MissingSuper
    @class_name = class_name
  end

  def template
    div(class: @class_name) { 'Hello' }
  end
end
