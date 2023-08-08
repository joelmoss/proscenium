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

  it 'should pass through props' do
    render Phlex::BasicReactComponent.new(props: { name: 'Joel' })

    expect(page.find(selector)['data-proscenium-component-props']).to be == %({"name":"Joel"})
  end
end
