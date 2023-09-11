# frozen_string_literal: true

class Phlex::Grandfather < Proscenium::Phlex
  def template
    h1(class: :@grandfather) { 'Grandfather' }
  end
end