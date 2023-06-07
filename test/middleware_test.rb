# frozen_string_literal: true

require_relative 'test_helper'

class MiddlewareTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
    Proscenium.config.cache_query_string = false
    Proscenium.reset_current_side_loaded
  end

  test 'unsupported path' do
    assert_raises ActionController::RoutingError do
      get '/db/some.js'
    end
  end

  test 'include_paths config' do
    Proscenium.config.include_paths << 'db'
    get '/db/some.js'

    assert_matches_snapshot response.body
  end

  test '.js' do
    get '/app/views/layouts/application.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_includes response.body, 'console.log("app/views/layouts/application.js");'
  end

  test '.ts' do
    get '/lib/foo.ts'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test '.tsx' do
    get '/lib/foo.tsx'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test '.css' do
    get '/app/views/layouts/application.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test '.module.css' do
    get '/lib/styles.module.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'import css module from js' do
    get '/lib/import_css_module.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'esbuild js compilation error' do
    assert_raises Proscenium::Esbuild::Golib::BuildError do
      get '/lib/includes_error.js'
    end
  end

  test 'js source map' do
    get '/lib/foo.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'jsx source map' do
    get '/lib/component.jsx.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'ts source map' do
    get '/lib/foo.ts.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'tsx source map' do
    get '/lib/foo.tsx.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'css source map' do
    get '/lib/foo.css.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'node module (pnpm)' do
    get '/node_modules/is-ip/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'cache_query_string should set cache header' do
    Proscenium.config.cache_query_string = 'v1'
    get '/lib/query_cache.js?v1'

    assert_includes response.headers['Cache-Control'], 'public'
  end

  test 'cache_query_string should propogate' do
    skip 'TODO'
    Proscenium.config.cache_query_string = 'v1'
    get '/lib/query_cache.js?v1'

    assert_matches_snapshot response.body
  end
end
