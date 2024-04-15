# frozen_string_literal: true

class Phlex::CssModuleHelperComponent < Proscenium::Phlex
  def view_template
    h1 class: css_module(:header) do
      'Hello'
    end
  end
end
