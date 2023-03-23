# frozen_string_literal: true

require_relative 'test_helper'

class NpmPrefixTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
    Proscenium.config.cache_query_string = false
    Proscenium.config.css_mixin_paths = Set[Rails.root.join('lib')]
    Proscenium.reset_current_side_loaded
  end

  test 'npm: regular dep' do
    get '/npm:is-ip'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'npm: dep file:... inside app' do
    get '/npm:internal-two/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'npm: dep link:... inside app' do
    get '/npm:internal-one-link/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'dep link:... outside app' do
    get '/lib/pnpm/link_outside_dep.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'npm: dep link:... outside app' do
    get '/npm:external-one-link/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'npm: sourcemap' do
    get '/npm:external-one-link/index.js.map'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end
end
