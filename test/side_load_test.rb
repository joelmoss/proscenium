# frozen_string_literal: true

require_relative 'test_helper'

class SideLoadTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.cache_query_string = false
    Proscenium::Importer.reset
  end

  test 'Side load layout and view' do
    get '/'

    assert_matches_snapshot response.body
  end

  test 'Side load action rendered view component' do
    get '/action_rendered_component'

    assert_matches_snapshot response.body
  end

  test 'Side load typescript' do
    get '/typescript'

    assert_matches_snapshot response.body
  end

  test 'Side load variant' do
    get '/variant'

    assert_matches_snapshot response.body
  end

  test 'Side load partial' do
    get '/sideloadpartial'

    assert_matches_snapshot response.body
  end

  test 'Side load vendored gem' do
    get '/vendored_gem'

    assert_matches_snapshot response.body
  end

  test 'Side load external gem' do
    get '/external_gem'

    assert_matches_snapshot response.body
  end
end
