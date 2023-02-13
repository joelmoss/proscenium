# frozen_string_literal: true

require_relative '../test_helper'

class Proscenium::Phlex::SideLoadTest < ActiveSupport::TestCase
  test 'side load component js and css' do
    Phlex::SideLoadView.new.call

    assert_equal({
                   js: Set['app/components/phlex/side_load_view.js'],
                   css: Set['app/components/phlex/side_load_view.css']
                 }, Proscenium::Current.loaded)
  end

  test 'nested side load' do
    Phlex::NestedSideLoadView.new.call

    assert_equal({
                   js: Set['app/components/phlex/side_load_view.js'],
                   css: Set['app/components/phlex/nested_side_load_view.css',
                            'app/components/phlex/side_load_view.css']
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
                   css: Set['app/components/phlex/side_load_css_module_view.module.css']
                 }, Proscenium::Current.loaded)
  end

  test 'side load from ruby gem' do
    Gem1::Views::User.new.call

    assert_equal({
                   js: Set['gem:gem1/app/views/user.js'],
                   css: Set['gem:gem1/app/views/user.css']
                 }, Proscenium::Current.loaded)
  end
end
