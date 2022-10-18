# frozen_string_literal: true

require_relative 'test_helper'

class MiddlewareTest < ActionDispatch::IntegrationTest
  test 'unsupported path' do
    assert_raises ActionController::RoutingError do
      get '/db/some.js'
    end
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

  test 'node module (pnpm)' do
    get '/node_modules/is-ip/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'outside root' do # rubocop:disable Minitest/MultipleAssertions
    path = 'lib/component_manager/test/outside_root'
    get "#{Dir.pwd}/#{path}/index.js?outsideRoot"

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'outsideroot', response.headers['X-Proscenium-Middleware']
    assert_match %(import isIp from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js";),
                 response.body
    assert_match "import foo from \"#{Dir.pwd}/#{path}/foo.js?outsideRoot\";", response.body
  end
end
