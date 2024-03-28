# frozen_string_literal: true

class Phlex::BasicView < Proscenium::Phlex
  def template
    super do
      h1 { 'Hello' }
    end
  end
end
