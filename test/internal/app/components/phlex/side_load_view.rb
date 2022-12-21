# frozen_string_literal: true

class Phlex::SideLoadView < Proscenium::Phlex
  include Proscenium::Phlex::Page

  def template
    div { 'Hello' }
  end
end
