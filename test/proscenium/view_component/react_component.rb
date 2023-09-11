# frozen_string_literal: true

require 'action_controller/test_case'

describe Proscenium::ViewComponent::ReactComponent do
  include ViewComponent::TestHelpers

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  let(:selector) do
    '[data-proscenium-component-path="/app/components/view_component/second_react/component.jsx"]'
  end

  it 'has data-proscenium-component attribute' do
    render_inline ViewComponent::SecondReact::Component.new

    expect(page.has_css?(selector)).to be == true
  end

  it 'has empty props' do
    render_inline ViewComponent::SecondReact::Component.new

    expect(page.find(selector)['data-proscenium-component-props']).to be == '{}'
  end

  it 'should pass through props' do
    render_inline ViewComponent::SecondReact::Component.new(props: { name: 'Joel' })

    expect(page.find(selector)['data-proscenium-component-props']).to be == %({"name":"Joel"})
  end
end
