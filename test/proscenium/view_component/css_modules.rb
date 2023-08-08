# frozen_string_literal: true

require 'action_controller/test_case'

describe Proscenium::ViewComponent::CssModules do
  include ViewComponent::TestHelpers

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with 'class: :@class' do
    it 'compiles css module' do
      render_inline ViewComponent::CssModule::Component.new

      expect(page.has_css?('h1.foo.hello52672a36', text: 'Hello')).to be == true
      expect(page.has_css?('h2.world52672a36', text: 'World')).to be == true
    end
  end

  with 'css_module! helper' do
    it 'helper raises on stylesheet not found' do
      skip 'needed?'

      expect do
        render_inline ViewComponent::CssModuleHelperOneComponent.new
      end.to raise_exception Proscenium::CssModule::StylesheetNotFound
    end
  end

  with 'css_module helper' do
    it 'replaces with CSS module name' do
      render_inline ViewComponent::CssModuleHelperTwoComponent.new

      expect(page.has_css?('h1.headera6157e6a', text: 'Hello')).to be == true
    end
  end
end
