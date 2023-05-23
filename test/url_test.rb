# frozen_string_literal: true

require_relative 'test_helper'

class UrlPrefixTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
    Proscenium.config.cache_query_string = false
    Proscenium.reset_current_side_loaded
  end

  test 'js' do
    get '/https%3A%2F%2Fga.jspm.io%2Fnpm%3Ais-fn%403.0.0%2Findex.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'url', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'js sourcemap' do
    get '/https%3A%2F%2Fga.jspm.io%2Fnpm%3Ais-fn%403.0.0%2Findex.js.map'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'url', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end
end
