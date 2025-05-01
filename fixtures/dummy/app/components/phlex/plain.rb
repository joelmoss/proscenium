# frozen_string_literal: true

class Phlex::Plain < Proscenium::Phlex
  def initialize(class_name)
    @class_name = class_name
  end

  def view_template
    div(class: @class_name) { 'Hello' }
  end
end
