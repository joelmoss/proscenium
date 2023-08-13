# frozen_string_literal: true

require 'action_controller/test_case'

describe Proscenium::ViewComponent::CssModules do
  include ViewComponent::TestHelpers

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with 'css_module helper' do
    it 'replaces with CSS module name' do
      render_inline ViewComponent::CssModuleHelperComponent.new

      expect(page.has_css?('h1.header-03d622d6', text: 'Hello')).to be == true
    end
  end
end
