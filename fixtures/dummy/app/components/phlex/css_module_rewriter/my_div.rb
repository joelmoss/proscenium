# frozen_string_literal: true

class Phlex::CssModuleRewriter::MyDiv < Proscenium::Phlex
  def initialize(**attrs)
    @attrs = attrs
  end

  def view_template(&)
    div(**@attrs, &)
  end
end
