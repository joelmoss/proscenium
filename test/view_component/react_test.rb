# frozen_string_literal: true

require_relative '../test_helper'

class ViewComponent::ReactTest < ViewComponent::TestCase
  setup do
    Proscenium.reset_current_side_loaded
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
    render_inline ViewComponent::SecondReact::Component.new
    data = JSON.parse(page.find('[data-proscenium-component]')['data-proscenium-component'])

    assert_equal(
      { 'path' => '/app/components/view_component/second_react/component', 'props' => {} },
      data
    )
  end

  test 'should pass through props' do
    render_inline ViewComponent::SecondReact::Component.new(props: { name: 'Joel' })
    data = JSON.parse(page.find('[data-proscenium-component]')['data-proscenium-component'])

    assert_equal(
      { 'path' => '/app/components/view_component/second_react/component',
        'props' => { 'name' => 'Joel' } },
      data
    )
  end
end
