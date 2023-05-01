# frozen_string_literal: true

require_relative '../test_helper'
require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

class Proscenium::Phlex::ReactComponentTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  setup do
    Proscenium.reset_current_side_loaded
  end

  test 'class names with .component' do
    render Phlex::ReactComponentWithComponentClass.new

    assert_selector '.componentManagedByProscenium.component66ab4da6'
  end

  test 'class names without .component' do
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
