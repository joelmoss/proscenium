# frozen_string_literal: true

require_relative '../test_helper'

# rubocop:disable Layout/LineLength
class Proscenium::Phlex::ResolveCssModuleTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper

  setup do
    Proscenium.reset_current_side_loaded
    Phlex::SideLoadCssModuleFromAttributesView.side_load_cache = Set.new
  end

  test 'should not use css module name' do
    result = render(Phlex::SideLoadCssModuleFromAttributesView.new('base'))

    assert_equal('<div class="base">Hello</div>', result)
  end

  test 'should use css module name' do
    result = render(Phlex::SideLoadCssModuleFromAttributesView.new(:@base))

    assert_equal('<div class="base02dcd653">Hello</div>', result)
  end

  test 'should raise when css_module class is used but stylesheet does not exist' do
    assert_raises Proscenium::CssModule::StylesheetNotFound do
      render Phlex::Plain.new(:@base)
    end
  end

  test 'should side load css module when bare path is given' do
    result = render(Phlex::SideLoadCssModuleFromAttributesView.new('mypackage/foo@foo'))

    assert_equal('<div class="foo39337ba7">Hello</div>', result)
    assert_equal({
                   js: Set[],
                   css: Set['/app/components/phlex/side_load_css_module_from_attributes_view.module.css',
                            '/packages/mypackage/foo.module.css']
                 },
                 Proscenium::Current.loaded)
  end

  test 'should side load css module when absolute path is given' do
    result = render(Phlex::SideLoadCssModuleFromAttributesView.new('/lib/styles@my_class'))

    assert_equal('<div class="myClass330940eb">Hello</div>', result)
    assert_equal({
                   js: Set[],
                   css: Set['/app/components/phlex/side_load_css_module_from_attributes_view.module.css',
                            '/lib/styles.module.css']
                 }, Proscenium::Current.loaded)
  end

  test 'should raise when path is given but stylesheet does not exist' do
    assert_raises Proscenium::Builder::ResolveError do
      render Phlex::SideLoadCssModuleFromAttributesView.new('/unknown@my_class')
    end
  end
end
# rubocop:enable Layout/LineLength
