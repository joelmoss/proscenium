# frozen_string_literal: true

require 'test_helper'

class ViewComponent::ReactTest < ViewComponent::TestCase
  include Rails::Dom::Testing::Assertions::DomAssertions

  test 'shallow react component' do
    result = render_inline ViewComponent::FirstReactComponent.new

    assert_dom_equal %(<div data-component='{"path":"/first_react_component","props":{}}'></div>),
                     result.to_html
  end

  test 'nested react component' do
    result = render_inline ViewComponent::SecondReact::Component.new

    assert_dom_equal %(<div data-component='{"path":"/second_react/component","props":{}}'></div>),
                     result.to_html
  end
end
