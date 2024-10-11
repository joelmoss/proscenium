# frozen_string_literal: true

require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'
require 'system_testing'

describe Proscenium::Phlex::ReactComponent do
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  # describe 'system' do
  #   include_context SystemTest

  #   it 'renders with react' do
  #     visit '/phlex/react/one'
  #     pp page.console_logs

  #     expect(page.has_button?('Click One!')).to be == true
  #   end
  # end

  let(:selector) do
    '[data-proscenium-component-path="/app/components/phlex/basic_react_component.jsx"]'
  end

  it 'has data-proscenium-component attribute' do
    render Phlex::BasicReactComponent.new

    expect(page.has_css?(selector)).to be == true
  end

  it 'forwards block to content' do
    render(Phlex::BasicReactComponent.new) { 'Hello' }

    expect(page.has_text?('Hello')).to be == true
  end

  it 'has empty props' do
    render Phlex::BasicReactComponent.new

    expect(page.find(selector)['data-proscenium-component-props']).to be == '{}'
  end

  with 'props' do
    it 'should pass through props' do
      render Phlex::BasicReactComponent.new(props: { name: 'Joel' })

      expect(page.find(selector)['data-proscenium-component-props']).to be == %({"name":"Joel"})
    end

    it 'should camelCase props keys' do
      render Phlex::BasicReactComponent.new(props: { first_name: 'Joel', 'some/last_name': 'Moss' })

      expect(page.find(selector)['data-proscenium-component-props']).to be == %({
        "firstName":"Joel", "some/lastName": "Moss"
      }).gsub(/[[:space:]]/, '')
    end
  end

  with 'root_tag' do
    def after(error = nil)
      Phlex::BasicReactComponent.root_tag = :div # reset
      super
    end

    it 'should use the given tag' do
      Phlex::BasicReactComponent.root_tag = :span
      render Phlex::BasicReactComponent.new

      expect(page.has_css?('span[data-proscenium-component-path]')).to be == true
    end
  end

  it 'should import component manager' do
    render Phlex::BasicReactComponent.new

    expect(Proscenium::Importer.imported['/@proscenium/react-manager/index.jsx']).to be == {
      js: { type: 'module' }
    }
  end

  # describe ':loader' do
  #   it 'show loader until component loads' do
  #     render Phlex::BasicReactComponent.new(loader: true)

  #     pp page.native.to_html

  #     expect(Proscenium::Importer.imported['/app/components/phlex/basic_react_component.jsx'][:lazy]).to be == true
  #   end
  # end

  describe 'lazy loading' do
    def after(error = nil)
      Phlex::BasicReactComponent.lazy = false # reset
      super
    end

    it 'should import component with `lazy: true` option' do
      render Phlex::BasicReactComponent.new(lazy: true)

      expect(Proscenium::Importer.imported['/app/components/phlex/basic_react_component.jsx'][:lazy]).to be == true
    end

    with '`.lazy = true`' do
      it 'adds lazy data attribute' do
        Phlex::BasicReactComponent.lazy = true
        render Phlex::BasicReactComponent.new

        expect(page.has_css?("#{selector}[data-proscenium-component-lazy]")).to be == true
      end
    end

    with '`.lazy = true` + `#lazy = false`' do
      it 'does not add lazy data attribute' do
        Phlex::BasicReactComponent.lazy = true
        render Phlex::BasicReactComponent.new(lazy: false)

        expect(page.has_css?("#{selector}[data-proscenium-component-lazy]")).to be == false
      end
    end

    with '`.lazy = false` (default) + `#lazy = true`' do
      it 'adds lazy data attribute' do
        render Phlex::BasicReactComponent.new(lazy: true)

        expect(page.has_css?("#{selector}[data-proscenium-component-lazy]")).to be == true
      end
    end

    # describe 'system' do
    #   include_context SystemTest

    #   it 'renders when intersecting' do
    #     visit '/phlex/react/lazy'

    #     expect(page.has_button?('Click One!', wait: false)).to be == false

    #     page.driver.scroll_to(0, 2000)

    #     expect(page.has_button?('Click One!')).to be == true
    #   end
    # end
  end

  with '`.forward_children = true`' do
    def after(error = nil)
      Phlex::React::ForwardChildren::Component.forward_children = true
      super
    end

    let(:selector) do
      '[data-proscenium-component-path="/app/components/phlex/react/forward_children/component.jsx"]'
    end

    it 'adds forward-children data attribute' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      expect(page.has_css?("#{selector}[data-proscenium-component-forward-children]")).to be == true
    end

    it 'renders content block as children' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      expect(page.has_text?('Hello')).to be == true
    end

    # with 'system' do
    #   include_context SystemTest

    #   it 'forwards block in children prop' do
    #     visit '/phlex/react/forward_children'

    #     expect(page.has_button?('hello')).to be == true
    #   end
    # end
  end

  with '`.forward_children = false`' do
    def before
      Phlex::React::ForwardChildren::Component.forward_children = false
      super
    end

    def after(error = nil)
      Phlex::React::ForwardChildren::Component.forward_children = true
      super
    end

    let(:selector) do
      '[data-proscenium-component-path="/app/components/phlex/react/forward_children/component.jsx"]'
    end

    it 'does not adds forward-children data attribute' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      expect(page.has_css?("#{selector}[data-proscenium-component-forward-children]")).to be == false
    end

    it 'renders content block as children' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      expect(page.has_text?('Hello')).to be == true
    end

    # with 'system' do
    #   include_context SystemTest

    #   it 'does not forward block in children prop' do
    #     visit '/phlex/react/forward_children'

    #     expect(page.has_button?('Click One!')).to be == true
    #   end
    # end
  end
end
