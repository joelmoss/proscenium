# frozen_string_literal: true

require_relative '../test_helper'

class Proscenium::Phlex::SideLoadTest < ActiveSupport::TestCase
  test 'side load component js and css' do
    Phlex::SideLoadView.new.call

    assert_equal({
                   js: Set[['f3a053ce', 'app/components/phlex/side_load_view.js']],
                   css: Set[['d11bbfa4', 'app/components/phlex/side_load_view.css']]
                 }, Proscenium::Current.loaded)
  end

  test 'nested side load' do
    Phlex::NestedSideLoadView.new.call

    assert_equal({
                   js: Set[['f3a053ce', 'app/components/phlex/side_load_view.js']],
                   css: Set[['871a6dce', 'app/components/phlex/nested_side_load_view.css'],
                            ['d11bbfa4', 'app/components/phlex/side_load_view.css']]
                 }, Proscenium::Current.loaded)
  end

  test 'should not side load css module when css_module not used' do
    Phlex::SideLoadCssModuleView.new(false).call

    assert_equal({
                   js: Set[],
                   css: Set[]
                 }, Proscenium::Current.loaded)
  end

  test 'should side load css module when css_module used' do
    Phlex::SideLoadCssModuleView.new(true).call

    assert_equal({
                   js: Set[],
                   css: Set[['03b26e31',
                             'app/components/phlex/side_load_css_module_view.module.css']]
                 }, Proscenium::Current.loaded)
  end

  test 'side load from ruby gem' do
    Gem1::Views::User.new.call

    assert_equal({
                   js: Set[['2f8d9a1c', 'ruby_gems/gem1/app/views/user.js']],
                   css: Set[]
                 }, Proscenium::Current.loaded)
  end
end
