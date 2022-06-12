require 'test_helper'

class LinkToHelperTest < ActionView::TestCase
  test 'should allow a shallow component' do
    assert_dom_equal(
      %(<a rel="nofollow" data-component="{&quot;props&quot;:{}}" href="/components/first_react_component">Hello</a>),
      link_to('Hello', FirstReactComponent.new)
    )
  end

  test 'should allow a nested component' do
    assert_dom_equal(
      %(<a rel="nofollow" data-component="{&quot;props&quot;:{}}"
        href="/components/second_react/component">Hello</a>),
      link_to('Hello', SecondReact::Component.new)
    )
  end

  test 'should allow a component with a block' do
    assert_dom_equal(
      %(<a rel="nofollow" data-component="{&quot;props&quot;:{}}"
        href="/components/first_react_component">Hello</a>),
      link_to(FirstReactComponent.new) { 'Hello' }
    )
  end

  test 'should passthrough other arguments' do
    assert_dom_equal(
      %(<a class="myClass" rel="nofollow" data-component="{&quot;props&quot;:{}}"
        href="/components/first_react_component">Hello</a>),
      link_to(FirstReactComponent.new, class: 'myClass') { 'Hello' }
    )
  end
end
