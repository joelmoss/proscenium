# frozen_string_literal: true

require_relative '../test_helper'

class ViewComponent::SideLoadTest < ViewComponent::TestCase
  include Rails::Dom::Testing::Assertions::DomAssertions

  setup do
    Proscenium::Importer.reset
  end

  test 'side load component js and css' do
    render_inline ViewComponent::FirstComponent.new

    assert_equal({
                   '/app/components/view_component/first_component.js' => { sideloaded: true },
                   '/app/components/view_component/first_component.css' => { sideloaded: true }
                 }, Proscenium::Importer.imported)
  end

  test 'side load css module' do
    render_inline ViewComponent::CssModule::Component.new

    assert_equal({
                   '/app/components/view_component/css_module/component.module.css' => { sideloaded: true }
                 }, Proscenium::Importer.imported)
  end

  test 'compile css classes' do
    result = render_inline ViewComponent::CssModule::Component.new

    assert_equal('<h1 class="base52672a36">Hello</h1>', result.to_html)
  end

  test 'css_module! helper raises on stylesheet not found' do
    assert_raises Proscenium::CssModule::StylesheetNotFound do
      render_inline ViewComponent::CssModuleHelperOneComponent.new
    end
  end

  test 'css_module helper side load stylesheet' do
    result = render_inline ViewComponent::CssModuleHelperTwoComponent.new

    assert_equal('<h1 class="headera6157e6a">Hello</h1>', result.to_html)
  end

  test 'css_module as attribute value' do
    result = render_inline ViewComponent::CssModuleHelperThree::Component.new

    assert_equal('<h1 class="header45dcbab9">Hello</h1>', result.to_html)
  end
end
