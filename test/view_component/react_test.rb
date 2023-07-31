# frozen_string_literal: true

require_relative '../test_helper'

# rubocop:disable Layout/LineLength
class ViewComponent::ReactTest < ViewComponent::TestCase
  setup do
    Proscenium::Importer.reset
  end

  test 'shallow react component' do
    result = render_inline ViewComponent::FirstReactComponent.new

    assert_matches_snapshot result.to_html
  end

  test 'nested react component' do
    result = render_inline ViewComponent::SecondReact::Component.new

    assert_matches_snapshot result.to_html
  end

  test 'data-proscenium-component attribute' do
    selector = '[data-proscenium-component-path="/app/components/view_component/second_react/component.jsx"]'
    render_inline ViewComponent::SecondReact::Component.new

    assert_selector selector
    assert_empty(JSON.parse(page.find(selector)['data-proscenium-component-props']))
  end

  test 'should pass through props' do
    selector = '[data-proscenium-component-path="/app/components/view_component/second_react/component.jsx"]'
    render_inline ViewComponent::SecondReact::Component.new(props: { name: 'Joel' })

    assert_selector selector
    assert_equal({ 'name' => 'Joel' },
                 JSON.parse(page.find(selector)['data-proscenium-component-props']))
  end
end
# rubocop:enable Layout/LineLength
