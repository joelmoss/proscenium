# frozen_string_literal: true

require_relative 'test_helper'

class SideLoadTest < ActionDispatch::IntegrationTest
  test '.append' do
    Proscenium::SideLoad.append 'app/views/layouts/application'

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css']
                 }, Proscenium::Current.loaded)
  end

  test '.append duplicate path' do
    Proscenium::SideLoad.append 'app/views/layouts/application'
    Proscenium::SideLoad.append 'app/views/layouts/application'

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css']
                 }, Proscenium::Current.loaded)
  end

  test '.append with different extensions' do
    Proscenium::SideLoad.append 'app/views/layouts/application', :js
    Proscenium::SideLoad.append 'app/views/layouts/application', :css

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css']
                 }, Proscenium::Current.loaded)
  end

  test '.append with extension argument' do
    Proscenium::SideLoad.append 'app/views/layouts/application', :js

    assert_equal({
                   js: Set['app/views/layouts/application.js'],
                   css: Set[]
                 }, Proscenium::Current.loaded)
  end

  test '.append css module' do
    Proscenium::SideLoad.append 'lib/styles.module', :css

    assert_equal({
                   js: Set[],
                   css: Set['lib/styles.module.css']
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

  test 'Side load action rendered component' do
    get '/action_rendered_component'

    assert_matches_snapshot response.body
  end
end
