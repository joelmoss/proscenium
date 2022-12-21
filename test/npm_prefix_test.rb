# frozen_string_literal: true

require_relative 'test_helper'

class NpmPrefixTest < ActionDispatch::IntegrationTest
  setup do
    # reset!
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
    Proscenium.config.cache_query_string = false
    Proscenium.config.css_mixin_paths = Set[Rails.root.join('lib')]
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
    get '/npm:internal-one/index.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'dep link:... outside app' do
    skip
    get '/lib/pnpm/link_outside_dep.js'
    pp response.body

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'esbuild', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'npm: dep link:... outside app' do
    skip
    get '/npm:external-one/index.js'
    pp response.body

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_equal 'npm', response.headers['X-Proscenium-Middleware']
    assert_matches_snapshot response.body
  end

  test 'npm: from ruby gem' do
    get '/npm:gem1/lib/gem1/gem1.js'

    assert_matches_snapshot response.body
  end

  test 'npm: sourcemap from ruby gem' do
    get '/npm:gem1/lib/gem1/gem1.js.map'

    assert_matches_snapshot response.body
  end
end
