# frozen_string_literal: true

require_relative 'test_helper'

class GemPrefixTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
    Proscenium.config.cache_query_string = false
    Proscenium.config.css_mixin_paths = Set[Rails.root.join('lib')]
    Proscenium.reset_current_side_loaded
  end

  test 'gem URl prefix' do
    get '/gem:gem1/app/views/user.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'gem', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'gem URL prefix for sourcemap' do
    get '/gem:gem1/app/views/user.js.map'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'gem', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'gem URL prefix for NPM dep' do
    assert_raises Proscenium::Middleware::Esbuild::CompileError do
      get '/gem:gem1/app/views/user.css'
    end
  end

  test 'gem URL prefix for unknown gem' do
    assert_raises ActionController::RoutingError do
      get '/gem:unknown/stuff.js'
    end
  end
end
