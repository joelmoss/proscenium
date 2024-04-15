# frozen_string_literal: true

class Phlex::SideLoadView < Proscenium::Phlex
  def view_template
    div { 'Hello' }
  end
end
