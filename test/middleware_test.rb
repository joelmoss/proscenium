# frozen_string_literal: true

require_relative 'test_helper'

class MiddlewareTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
    Proscenium.config.cache_query_string = false
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
    assert_matches_snapshot response.body
  end

  test '.jsx' do
    get '/lib/component.jsx'

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

  test 'injects /lib/custom_media_queries.css if present' do
    get '/lib/with_custom_media.css'

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

  test '/proscenium-runtime/auto_reload.js' do
    get '/proscenium-runtime/auto_reload.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'esbuild js compilation error' do
    get '/lib/includes_error.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'source map' do
    get '/lib/foo.js.map'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'jsx source map' do
    get '/lib/component.jsx.map'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'node module (pnpm)' do
    get '/node_modules/is-ip/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'url: modules' do
    get '/url:https%3A%2F%2Fga.jspm.io%2Fnpm%3Ais-fn%403.0.0%2Findex.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'url', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'url: modules sourcemap' do
    get '/url:https%3A%2F%2Fga.jspm.io%2Fnpm%3Ais-fn%403.0.0%2Findex.js.map'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'url', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'outside root' do # rubocop:disable Minitest/MultipleAssertions
    path = 'test/outside_root'
    get "#{Dir.pwd}/#{path}/index.js?outsideRoot"

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'outsideroot', response.headers['X-Proscenium-Middleware']
    assert_match %(import isIp from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js";),
                 response.body
    assert_match "import foo from \"#{Dir.pwd}/#{path}/foo.js?outsideRoot\";", response.body
  end

  test 'cache_query_string should set cache header' do
    Proscenium.config.cache_query_string = 'v1'
    get '/lib/query_cache.js?v1'

    assert_includes response.headers['Cache-Control'], 'public'
  end

  test 'cache_query_string should propogate' do
    Proscenium.config.cache_query_string = 'v1'
    get '/lib/query_cache.js?v1'

    assert_matches_snapshot response.body
  end

  test 'from ruby gem' do
    get '/ruby_gems/gem1/lib/gem1/gem1.js'

    assert_matches_snapshot response.body
  end

  test 'sourcemap from ruby gem' do
    get '/ruby_gems/gem1/lib/gem1/gem1.js.map'

    assert_matches_snapshot response.body
  end
end
