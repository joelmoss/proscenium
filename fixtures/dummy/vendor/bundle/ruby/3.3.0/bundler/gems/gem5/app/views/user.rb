# frozen_string_literal: true

module Gem5::Views
  class User < Proscenium::Phlex
    def view_template
      h1 { 'Hello' }
    end
  end
end
