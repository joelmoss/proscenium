# frozen_string_literal: true

class Phlex::SideLoadCssModuleView < Proscenium::Phlex
  def template
    div class: css_module(:base) { 'Hello' }
  end
end
