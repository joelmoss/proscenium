# frozen_string_literal: true

require_relative '../system_test_case'
require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

class Proscenium::Phlex::ReactComponentTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  setup do
    Proscenium.reset_current_side_loaded
  end

  class SystemTest < SystemTestCase
    test 'with side loaded component.module.css' do
      visit '/phlex/react/one'

      href = '/app/components/phlex/react/one/component.module.css'

      assert_selector 'button'
      assert_selector "head>link[href='#{href}']", visible: false
      refute_selector "head>style[data-href='#{href}']", visible: false
      assert_selector '.componentManagedByProscenium.component2d707834'
    end
  end

  test 'without side loaded component.module.css' do
    render Phlex::BasicReactComponent.new

    assert_selector '.componentManagedByProscenium.component'
  end

  test 'data-component attribute' do
    render Phlex::BasicReactComponent.new
    data = JSON.parse(page.find('.componentManagedByProscenium')['data-component'])

    assert_equal(
      { 'path' => '/app/components/phlex/basic_react_component', 'props' => {}, 'lazy' => true },
      data
    )
  end

  test 'should set lazy as false' do
    render Phlex::BasicReactComponent.new(lazy: false)
    data = JSON.parse(page.find('.componentManagedByProscenium')['data-component'])

    assert_equal(
      { 'path' => '/app/components/phlex/basic_react_component', 'props' => {}, 'lazy' => false },
      data
    )
  end

  test 'should pass through props' do
    render Phlex::BasicReactComponent.new(props: { name: 'Joel' })
    data = JSON.parse(page.find('.componentManagedByProscenium')['data-component'])

    assert_equal(
      { 'path' => '/app/components/phlex/basic_react_component',
        'props' => { 'name' => 'Joel' },
        'lazy' => true },
      data
    )
  end

  test 'should contain a div "loading"' do
    render Phlex::BasicReactComponent.new

    assert_selector 'div>div', text: 'loading...'
  end

  test 'should accept a block' do
    skip
    render(Phlex::BasicReactComponent.new) { span { 'hello' } }
    pp page.native

    assert_selector 'div>div', text: 'loading...'
  end
end
