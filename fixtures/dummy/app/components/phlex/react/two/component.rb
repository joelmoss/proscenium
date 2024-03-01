# frozen_string_literal: true

class Phlex::React::Two::Component < Proscenium::Phlex::ReactComponent
  def template
    super(class: :@foo)
  end
end
