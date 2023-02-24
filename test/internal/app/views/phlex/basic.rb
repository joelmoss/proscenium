# frozen_string_literal: true

class Views::Phlex::Basic < Proscenium::Phlex
  include Proscenium::Phlex::Layout

  def template
    h1 { 'Hello' }
  end
end
