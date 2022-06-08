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

  test 'react middleware' do
    Rails.application.config.proscenium.middleware = [:react]

    get '/lib/component.jsx'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'react', response.headers['X-Proscenium-Middleware']
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

  test 'build js sourcemap' do
    Rails.application.config.proscenium.middleware = [:javascript]

    get '/lib/foo.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'javascript', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build jsx sourcemap' do
    Rails.application.config.proscenium.middleware = [:react]

    get '/lib/component.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'react', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build runtime js source map' do
    Rails.application.config.proscenium.middleware = [:runtime]

    get '/proscenium-runtime/import_css.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build /proscenium-runtime/import_css.js' do
    Rails.application.config.proscenium.middleware = [:runtime]

    get '/proscenium-runtime/import_css.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build css' do
    Rails.application.config.proscenium.middleware = [:stylesheet]

    get '/app/views/layouts/application.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_equal 'stylesheet', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'build css module' do
    Rails.application.config.proscenium.middleware = [:stylesheet]

    get '/lib/styles.module.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_equal 'stylesheet', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'import css module from js' do
    Rails.application.config.proscenium.middleware = %i[javascript stylesheet]

    get '/lib/import_css_module.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'javascript', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end
end
