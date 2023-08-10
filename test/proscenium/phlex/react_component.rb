# frozen_string_literal: true

require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

describe Proscenium::Phlex::ReactComponent do
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  let(:selector) do
    '[data-proscenium-component-path="/app/components/phlex/basic_react_component.jsx"]'
  end

  it 'has data-proscenium-component attribute' do
    render Phlex::BasicReactComponent.new

    expect(page.has_css?(selector)).to be == true
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

    it 'should camelCase keys' do
      render Phlex::BasicReactComponent.new(props: { first_name: 'Joel', 'some/last_name': 'Moss' })

      expect(page.find(selector)['data-proscenium-component-props']).to be == %({
        "firstName":"Joel", "some/lastName": "Moss"
      }).gsub(/[[:space:]]/, '')
    end
  end

  with 'root_tag' do
    def after
      Phlex::BasicReactComponent.root_tag = :div # reset
    end

    it 'should use the given tag' do
      Phlex::BasicReactComponent.root_tag = :span
      render Phlex::BasicReactComponent.new

      expect(page.has_css?('span[data-proscenium-component-path]')).to be == true
    end
  end

  it 'should import component manager' do
    render Phlex::BasicReactComponent.new

    expect(Proscenium::Importer.imported['/lib/manager/index.jsx']).to be == {}
  end

  describe 'lazy loading' do
    def after
      Phlex::BasicReactComponent.lazy = false # reset
    end

    it 'should import component with `lazy: true` option' do
      render Phlex::BasicReactComponent.new(lazy: true)

      expect(Proscenium::Importer.imported['/app/components/phlex/basic_react_component.jsx'][:lazy]).to be == true
    end

    with '`.lazy = true`' do
      it 'should be lazy' do
        Phlex::BasicReactComponent.lazy = true
        render Phlex::BasicReactComponent.new

        expect(page.has_css?("#{selector}[data-proscenium-component-lazy]")).to be == true
      end
    end

    with '`.lazy = true` + `#lazy = false`' do
      it 'should not be lazy' do
        Phlex::BasicReactComponent.lazy = true
        render Phlex::BasicReactComponent.new(lazy: false)

        expect(page.has_css?("#{selector}[data-proscenium-component-lazy]")).to be == false
      end
    end

    with '`.lazy = false` (dfefault) + `#lazy = true`' do
      it 'should be lazy' do
        render Phlex::BasicReactComponent.new(lazy: true)

        expect(page.has_css?("#{selector}[data-proscenium-component-lazy]")).to be == true
      end
    end
  end
end
