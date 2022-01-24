# frozen_string_literal: true

require_relative 'test_helper'

class SideLoadTest < ActionDispatch::IntegrationTest
  test '.append' do
    Proscenium::SideLoad.append 'app/views/layouts/application'

    assert_equal({
                   entries: Set['app/views/layouts/application'],
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css']
                 }, Proscenium::Current.loaded)
  end

  test '.append duplicate path' do
    Proscenium::SideLoad.append 'app/views/layouts/application'
    Proscenium::SideLoad.append 'app/views/layouts/application'

    assert_equal({
                   entries: Set['app/views/layouts/application'],
                   js: Set['app/views/layouts/application.js'],
                   css: Set['app/views/layouts/application.css']
                 }, Proscenium::Current.loaded)
  end

  test 'Side load layout and view' do
    get '/'

    assert_matches_snapshot response.body
  end
end
