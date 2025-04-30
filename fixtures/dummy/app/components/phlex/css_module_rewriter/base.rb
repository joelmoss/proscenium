# frozen_string_literal: true

module Phlex::CssModuleRewriter
  class Base < Proscenium::Phlex
    def my_div(**attrs, &)
      render MyDiv.new(**attrs, &)
    end
  end
end
