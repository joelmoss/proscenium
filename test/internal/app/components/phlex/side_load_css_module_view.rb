# frozen_string_literal: true

class Phlex::SideLoadCssModuleView < Proscenium::Phlex
  def initialize(use_css_module) # rubocop:disable Lint/MissingSuper:
    @use_css_module = use_css_module
  end

  def template
    if @use_css_module
      div class: css_module(:base) { 'Hello' }
    else
      div { 'Hello' }
    end
  end
end
