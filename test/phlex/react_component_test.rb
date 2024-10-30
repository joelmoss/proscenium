# frozen_string_literal: true

require 'test_helper'
require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

class Proscenium::Phlex::ReactComponentTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

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

    assert page.has_css?(selector)
  end

  it 'forwards block to content' do
    render(Phlex::BasicReactComponent.new) { 'Hello' }

    assert page.has_text?('Hello')
  end

  it 'has empty props' do
    render Phlex::BasicReactComponent.new

    assert_equal '{}', page.find(selector)['data-proscenium-component-props']
  end

  context 'props' do
    it 'should pass through props' do
      render Phlex::BasicReactComponent.new(props: { name: 'Joel' })

      assert_equal %({"name":"Joel"}), page.find(selector)['data-proscenium-component-props']
    end

    it 'should camelCase props keys' do
      render Phlex::BasicReactComponent.new(props: { first_name: 'Joel', 'some/last_name': 'Moss' })

      assert_equal(
        %({
          "firstName":"Joel", "some/lastName": "Moss"
        }).gsub(/[[:space:]]/, ''),
        page.find(selector)['data-proscenium-component-props']
      )
    end
  end

  context 'root_tag' do
    after do
      Phlex::BasicReactComponent.root_tag = :div # reset
    end

    it 'should use the given tag' do
      Phlex::BasicReactComponent.root_tag = :span
      render Phlex::BasicReactComponent.new

      assert page.has_css?('span[data-proscenium-component-path]')
    end
  end

  it 'should import component manager' do
    render Phlex::BasicReactComponent.new

    assert_equal({
                   js: { type: 'module' }
                 }, Proscenium::Importer.imported['/@proscenium/react-manager/index.jsx'])
  end

  describe 'lazy loading' do
    after do
      Phlex::BasicReactComponent.lazy = false # reset
    end

    it 'should import component with `lazy: true` option' do
      render Phlex::BasicReactComponent.new(lazy: true)

      assert Proscenium::Importer.imported['/app/components/phlex/basic_react_component.jsx'][:lazy]
    end

    context '`.lazy = true`' do
      it 'adds lazy data attribute' do
        Phlex::BasicReactComponent.lazy = true
        render Phlex::BasicReactComponent.new

        assert page.has_css?("#{selector}[data-proscenium-component-lazy]")
      end
    end

    context '`.lazy = true` + `#lazy = false`' do
      it 'does not add lazy data attribute' do
        Phlex::BasicReactComponent.lazy = true
        render Phlex::BasicReactComponent.new(lazy: false)

        assert_not page.has_css?("#{selector}[data-proscenium-component-lazy]")
      end
    end

    context '`.lazy = false` (default) + `#lazy = true`' do
      it 'adds lazy data attribute' do
        render Phlex::BasicReactComponent.new(lazy: true)

        assert page.has_css?("#{selector}[data-proscenium-component-lazy]")
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

  context '`.forward_children = true`' do
    after do
      Phlex::React::ForwardChildren::Component.forward_children = true
    end

    let(:selector) do
      '[data-proscenium-component-path="' \
        '/app/components/phlex/react/forward_children/component.jsx"]'
    end

    it 'adds forward-children data attribute' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      assert page.has_css?("#{selector}[data-proscenium-component-forward-children]")
    end

    it 'renders content block as children' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      assert page.has_text?('Hello')
    end

    # context 'system' do
    #   include_context SystemTest

    #   it 'forwards block in children prop' do
    #     visit '/phlex/react/forward_children'

    #     expect(page.has_button?('hello')).to be == true
    #   end
    # end
  end

  context '`.forward_children = false`' do
    before do
      Phlex::React::ForwardChildren::Component.forward_children = false
    end

    after do
      Phlex::React::ForwardChildren::Component.forward_children = true
    end

    let(:selector) do
      '[data-proscenium-component-path="' \
        '/app/components/phlex/react/forward_children/component.jsx"]'
    end

    it 'does not adds forward-children data attribute' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      assert_not page.has_css?("#{selector}[data-proscenium-component-forward-children]")
    end

    it 'renders content block as children' do
      render(Phlex::React::ForwardChildren::Component.new) { 'Hello' }

      assert page.has_text?('Hello')
    end

    # context 'system' do
    #   include_context SystemTest

    #   it 'does not forward block in children prop' do
    #     visit '/phlex/react/forward_children'

    #     expect(page.has_button?('Click One!')).to be == true
    #   end
    # end
  end
end
