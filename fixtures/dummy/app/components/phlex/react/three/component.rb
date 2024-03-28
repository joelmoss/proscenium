# frozen_string_literal: true

class Phlex::React::Three::Component < Proscenium::Phlex::ReactComponent
  def template
    super(class: :foo)
  end
end
