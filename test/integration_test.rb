# frozen_string_literal: true

require_relative 'test_helper'

class IntegrationTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.proscenium.middleware = [:static]
  end

  teardown do
    Rails.application.config.proscenium.middleware = Proscenium::DEFAULT_MIDDLEWARE
  end

  test 'static middleware' do
    Rails.application.config.proscenium.middleware = [:static]

    get '/app/views/layouts/application.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'static', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'no middleware' do
    Rails.application.config.proscenium.middleware = []

    assert_raises ActionController::RoutingError do
      get '/app/views/layouts/application.js'
    end
  end

  test 'esbuild middleware' do
    Rails.application.config.proscenium.middleware = [:esbuild]

    get '/lib/component.jsx'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'stylesheet not found' do
    assert_raises ActionController::RoutingError do
      get '/notfound.css'
    end
  end

  test 'javascript not found' do
    assert_raises ActionController::RoutingError do
      get '/notfound.js'
    end
  end

  test 'build files ending with .css' do
    get '/app/views/layouts/application.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_matches_snapshot response.body
  end

  test 'middleware determined by params' do
    Rails.application.config.proscenium.middleware.prepend :jsx

    get '/lib/node_env.js?middleware=esbuild'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build js sourcemap' do
    Rails.application.config.proscenium.middleware = [:esbuild]

    get '/lib/foo.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build jsx sourcemap' do
    Rails.application.config.proscenium.middleware = [:esbuild]

    get '/lib/component.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build runtime js source map' do
    Rails.application.config.proscenium.middleware = [:runtime]

    get '/proscenium-runtime/adopt_css_module.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build /proscenium-runtime/adopt_css_module.js' do
    Rails.application.config.proscenium.middleware = [:runtime]

    get '/proscenium-runtime/adopt_css_module.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end
end
