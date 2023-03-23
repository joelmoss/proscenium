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
end
