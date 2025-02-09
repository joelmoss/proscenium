# frozen_string_literal: true

require 'test_helper'

DummyApp = ->(_) { [404, {}, []] }
HelloApp = ->(_) { [200, { 'Content-Type' => 'text/plain' }, ['Hello, World!']] }

class Proscenium::MiddlewareTest < ActiveSupport::TestCase
  attr_reader :response

  before do
    Proscenium.config.cache_query_string = false
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  let(:subject) { Proscenium::Middleware }
  let(:app) { subject.new DummyApp }

  ['js', 'mjs', 'ts', 'jsx', 'tsx', 'css', 'js.map', 'mjs.map', 'jsx.map', 'ts.map', 'tsx.map',
   'css.map'].each do |extension|
    it "serves .#{extension}" do
      get "/lib/extensions/foo.#{extension}"

      assert_equal 200, response.status
    end
  end

  ['config/foo.js', 'app/views/foo.js', 'lib/foo.js', 'vendor/foo.js',
   'node_modules/mypackage/index.js'].each do |path|
    it "serves from #{path}" do
      get "/#{path}"

      assert_equal 200, response.status
    end
  end

  it 'raises on compilation error' do
    assert_raises Proscenium::Builder::BuildError do
      get '/lib/includes_error.js'
    end
  end

  context 'unsupported path' do
    let(:app) { subject.new HelloApp }

    it 'passes through' do
      get '/db/some.js'

      assert_equal 'Hello, World!', response.body
    end
  end

  context 'vendored engine with package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem1/lib/gem1/gem1.js'

      assert_includes response.body, 'console.log("gem1");'
    end
  end

  context 'vendored engine without package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem3/lib/gem3/gem3.js'

      assert_includes response.body, 'console.log("gem3");'
    end
  end

  context 'un-vendored engine with package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem2/lib/gem2/gem2.js'

      assert_includes response.body, 'console.log("gem2");'
    end
  end

  context 'un-vendored engine without package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem4/lib/gem4/gem4.js'

      assert_includes response.body, 'console.log("gem4");'
    end
  end

  it 'serves javascript' do
    get '/lib/foo.js'

    assert_equal 'application/javascript', response.headers['Content-Type']
    assert_includes response.body.squish, %(
      console.log("/lib/foo.js");
      //# sourceMappingURL=foo.js.map
    ).squish
  end

  it 'serves javascript source map' do
    get '/lib/foo.js.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_includes response.body, %("sources": ["../../../lib/foo.js"])
  end

  it 'serves css' do
    get '/lib/foo.css'

    assert_includes response.body.squish, %(
      .body { color: red; }
      /*# sourceMappingURL=foo.css.map */
    ).squish
  end

  it 'serves css source map' do
    get '/lib/foo.css.map'

    assert_equal 'application/json', response.headers['Content-Type']
    assert_includes response.body, %("sources": ["../../../lib/foo.css"])
  end

  it 'serves css module' do
    get '/lib/styles.module.css'

    assert_equal 'text/css', response.headers['Content-Type']
    assert_includes response.body.squish, %(
      .myClass-330940eb { color: pink; }
      /*# sourceMappingURL=styles.module.css.map */
    ).squish
  end

  it 'serves proscenium/* runtime libs' do
    get '/proscenium/test.js'

    assert_includes response.body, 'console.log("proscenium/test.js")'
  end

  context 'cache_query_string' do
    it 'should set cache header ' do
      Proscenium.config.cache_query_string = 'v1'
      get '/lib/query_cache.js'

      assert_equal 'public, max-age=2592000', response.headers['Cache-Control']
    end

    it 'should propogate cache_query_string' do
      skip 'TODO'

      Proscenium.config.cache_query_string = 'v1'
      get '/lib/query_cache.js?v1'

      assert_includes response.body, 'console.log("/lib/query_cache.js")'
    end
  end

  private

  def get(path)
    @response = Rack::MockRequest.new(app).request('GET', path)
  end
end
