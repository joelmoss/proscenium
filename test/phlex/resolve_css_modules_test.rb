# frozen_string_literal: true

require_relative '../test_helper'

class Proscenium::Phlex::ResolveCssModuleTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper

  setup do
    Proscenium.reset_current_side_loaded
  end

  test 'should not side load css module when css_module class is not used' do
    render Phlex::SideLoadCssModuleFromAttributesView.new('base')

    assert_equal({ js: Set[], css: Set[] }, Proscenium::Current.loaded)
  end

  test 'should side load css module when css_module class is used' do
    render Phlex::SideLoadCssModuleFromAttributesView.new(:@base)

    assert_equal({
                   js: Set[],
                   css: Set['app/components/phlex/side_load_css_module_from_attributes_view.module.css']
                 }, Proscenium::Current.loaded)
  end
end
