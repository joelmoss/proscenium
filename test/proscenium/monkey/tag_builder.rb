# frozen_string_literal: true

require 'action_controller/test_case'

describe Proscenium::Monkey::TagBuilder do
  include ViewComponent::TestHelpers

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with 'erb templates' do
    attr_reader :page

    def render(output)
      @page = Capybara::Node::Simple.new(output)
    end

    it 'replaces CSS module names' do
      render BarePagesController.render :tag_builder

      expect(page.has_css?('h1.foo.hello-a179f356', text: 'Hello')).to be == true
      expect(page.has_css?('h2.world-a179f356', text: 'World')).to be == true
    end
  end

  with 'ViewComponents' do
    it 'replaces CSS module names' do
      render_inline ViewComponent::CssModule::Component.new

      expect(page.has_css?('h1.foo.hello-52672a36', text: 'Hello')).to be == true
      expect(page.has_css?('h2.world-52672a36', text: 'World')).to be == true
    end
  end
end
