# frozen_string_literal: true

require_relative 'test_helper'

class MiddlewareTest < ActionDispatch::IntegrationTest
  teardown do
    Rails.application.config.proscenium.glob_types = Proscenium::DEFAULT_GLOB_TYPES
  end

  test 'unsupported path' do
    assert_raises ActionController::RoutingError do
      get '/app/controllers/some.js'
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
    assert_equal 'parcelcss', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test '.module.css' do
    get '/lib/styles.module.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_equal 'parcelcss', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'import css module from js' do
    get '/lib/import_css_module.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test '/proscenium-runtime/import_css.js' do
    get '/proscenium-runtime/import_css.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'import proscenium/component_manager' do
    get '/lib/import_proscenium_component_manager.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'import map in runtime file' do
    get '/proscenium-runtime/component_manager/render_component.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end
end
