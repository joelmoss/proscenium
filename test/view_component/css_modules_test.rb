# frozen_string_literal: true

require 'test_helper'

class Proscenium::ViewComponent::CssModulesTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  context 'css_module helper' do
    it 'replaces with CSS module name' do
      render_inline ViewComponent::CssModuleHelperComponent.new

      assert page.has_css?('h1.header-03d622d6', text: 'Hello')
    end

    it 'side loads css module' do
      render_inline ViewComponent::CssModuleHelperComponent.new

      assert_equal({
                     '/app/components/view_component/css_module_helper_component.module.css' => {
                       digest: '03d622d6'
                     }
                   }, Proscenium::Importer.imported)
    end
  end
end
