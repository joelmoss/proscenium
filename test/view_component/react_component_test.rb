# frozen_string_literal: true

require 'test_helper'

class Proscenium::ViewComponent::ReactComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  let(:selector) do
    '[data-proscenium-component-path="/app/components/view_component/second_react/component.jsx"]'
  end

  it 'has data-proscenium-component attribute' do
    render_inline ViewComponent::SecondReact::Component.new

    assert page.has_css?(selector)
  end

  it 'has empty props' do
    render_inline ViewComponent::SecondReact::Component.new

    assert_equal '{}', page.find(selector)['data-proscenium-component-props']
  end

  it 'should pass through props' do
    render_inline ViewComponent::SecondReact::Component.new(props: { name: 'Joel' })

    assert_equal %({"name":"Joel"}), page.find(selector)['data-proscenium-component-props']
  end
end
