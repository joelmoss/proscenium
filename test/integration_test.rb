# frozen_string_literal: true

require_relative 'test_helper'

class IntegrationTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.proscenium.middleware = [:static]
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

  # focus
  # test 'swc middleware' do
  #   Rails.application.config.proscenium.middleware.prepend :swc

  #   get '/lib/component.jsx'

  #   assert_equal 'application/javascript', response.headers['Content-Type']
  #   assert_equal 'swc', response.headers['X-Proscenium-Middleware']
  #   assert_matches_snapshot response.body
  # end

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

  # test 'build /proscenium-runtime/*' do
  #   get '/proscenium-runtime/adopt_css_module.js'

  #   assert_equal 'application/javascript', response.headers['Content-Type']
  #   assert_equal 'runtime', response.headers['X-Proscenium-Middleware']
  #   assert_matches_snapshot response.body
  # end
end
