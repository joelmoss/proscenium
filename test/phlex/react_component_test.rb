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
      skip 'FIXME'

      visit '/phlex/react/one'

      href = '/app/components/phlex/react/one/component.module.css'

      assert_selector 'button'
      assert_selector "head>link[href='#{href}']", visible: false
      refute_selector "head>style[data-href='#{href}']", visible: false
      assert_selector '[data-proscenium-component]'
    end
  end

  test 'redefining template' do
    view = Class.new(Proscenium::Phlex::ReactComponent) do
      def template
        super class: 'foo' do
          span { 'hello' }
        end
      end
    end
    render view.new

    assert_selector '.foo'
    assert_text 'hello'
  end

  test 'data-proscenium-component attribute' do
    render Phlex::BasicReactComponent.new
    data = JSON.parse(page.find('[data-proscenium-component]')['data-proscenium-component'])

    assert_equal(
      { 'path' => '/app/components/phlex/basic_react_component', 'props' => {} },
      data
    )
  end

  test 'should pass through props' do
    render Phlex::BasicReactComponent.new(props: { name: 'Joel' })
    data = JSON.parse(page.find('[data-proscenium-component]')['data-proscenium-component'])

    assert_equal(
      { 'path' => '/app/components/phlex/basic_react_component', 'props' => { 'name' => 'Joel' } },
      data
    )
  end
end
