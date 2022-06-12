# frozen_string_literal: true

require_relative 'test_helper'

class ComponentTest < ViewComponent::TestCase
  include Rails::Dom::Testing::Assertions::DomAssertions

  test 'side load component js and css' do
    render_inline FirstComponent.new

    assert_equal({
                   js: Set['app/components/first_component.js'],
                   css: Set['app/components/first_component.css']
                 }, Proscenium::Current.loaded)
  end

  test 'css_module helper raises on stylesheet not found' do
    assert_raises Proscenium::SideLoad::NotFound do
      render_inline CssModuleHelperOneComponent.new
    end
  end

  test 'css_module helper side load stylesheet' do
    render_inline CssModuleHelperTwoComponent.new

    assert_equal({ js: Set[], css: Set['app/components/css_module_helper_two_component.module.css'] },
                 Proscenium::Current.loaded)
  end

  test 'css_module html tag attribute' do
    render_inline CssModuleHelperThree::Component.new

    assert_equal({ js: Set[], css: Set['app/components/css_module_helper_three/component.module.css'] },
                 Proscenium::Current.loaded)
  end
end
