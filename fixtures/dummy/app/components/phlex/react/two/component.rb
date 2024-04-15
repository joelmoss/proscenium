# frozen_string_literal: true

class Phlex::React::Two::Component < Proscenium::Phlex::ReactComponent
  def view_template
    super(class: :@foo)
  end
end
