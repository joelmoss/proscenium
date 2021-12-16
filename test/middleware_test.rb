# frozen_string_literal: true

require_relative 'test_helper'

class MiddlewareTest < ActionDispatch::IntegrationTest
  test 'build files ending with .js' do
    get '/app/views/layouts/application.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
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
end
