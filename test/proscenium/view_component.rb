# frozen_string_literal: true

require 'action_controller/test_case'

describe Proscenium::ViewComponent do
  include ViewComponent::TestHelpers

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  it 'side loads component js and css' do
    render_inline ViewComponent::FirstComponent.new

    expect(Proscenium::Importer.imported).to be == {
      '/app/components/view_component/first_component.js' => { sideloaded: true },
      '/app/components/view_component/first_component.css' => { sideloaded: true }
    }
  end

  with ':@css_module_name' do
    it 'side loads css module' do
      render_inline ViewComponent::CssModule::Component.new

      expect(Proscenium::Importer.imported).to be == {
        '/app/components/view_component/css_module/component.module.css' => {
          sideloaded: true, digest: '52672a36'
        }
      }
    end
  end
end
