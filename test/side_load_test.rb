# frozen_string_literal: true

require_relative 'test_helper'

class SideLoadTest < ActionDispatch::IntegrationTest
  test '.append' do
    Proscenium::SideLoad.append 'app/views/layouts/application'

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css'],
                   cssm: Set[]
                 }, Proscenium::Current.loaded)
  end

  test '.append duplicate path' do
    Proscenium::SideLoad.append 'app/views/layouts/application'
    Proscenium::SideLoad.append 'app/views/layouts/application'

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css'],
                   cssm: Set[]
                 }, Proscenium::Current.loaded)
  end

  test '.append with different extensions' do
    Proscenium::SideLoad.append 'app/views/layouts/application', :js
    Proscenium::SideLoad.append 'app/views/layouts/application', :css

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css'],
                   cssm: Set[]
                 }, Proscenium::Current.loaded)
  end

  test '.append with extension argument' do
    Proscenium::SideLoad.append 'app/views/layouts/application', :js

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set[],
                   cssm: Set[]
                 }, Proscenium::Current.loaded)
  end

  test '.append css module' do
    Proscenium::SideLoad.append 'app/views/layouts/application', :cssm

    assert_equal({
                   js: Set[],
                   cssm: Set['app/views/layouts/application.css'],
                   css: Set[]
                 }, Proscenium::Current.loaded)
  end

  test '.append with unknown extension argument' do
    assert_raises ArgumentError do
      Proscenium::SideLoad.append 'app/views/layouts/application', :foo
    end
  end

  test 'Side load layout and view' do
    get '/'

    assert_matches_snapshot response.body
  end
end
