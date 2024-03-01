# frozen_string_literal: true

module Gem1::Views
  class User < Proscenium::Phlex
    def template
      h1 { 'Hello' }
    end
  end
end
