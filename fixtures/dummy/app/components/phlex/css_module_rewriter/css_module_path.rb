# frozen_string_literal: true

module Phlex::CssModuleRewriter
  class CssModulePath < Base
    def self.css_module_path
      Pathname.new(__dir__).join('class_css_module.module.css')
    end

    def view_template
      my_div(class: :@title) { 'Hello' }
    end
  end
end
