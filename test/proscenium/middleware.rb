# frozen_string_literal: true

DummyApp = ->(_) { [404, {}, []] }
HelloApp = ->(_) { [200, { 'Content-Type' => 'text/plain' }, ['Hello, World!']] }

SupportedExtension = Sus::Shared('supported file extension') do |args|
  it "serves .#{args[:extension]}" do
    get "/lib/extensions/foo.#{args[:extension]}"

    expect(response.status).to be == 200
  end
end

IncludedPath = Sus::Shared('included path') do |args|
  it "serves from #{args[:path]}" do
    get "/#{args[:path]}"

    expect(response.status).to be == 200
  end
end

describe Proscenium::Middleware do
  attr_reader :response

  def before
    Proscenium.config.cache_query_string = false
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  let(:app) { subject.new DummyApp }

  it_behaves_like SupportedExtension, { extension: 'js' }
  it_behaves_like SupportedExtension, { extension: 'mjs' }
  it_behaves_like SupportedExtension, { extension: 'ts' }
  it_behaves_like SupportedExtension, { extension: 'jsx' }
  it_behaves_like SupportedExtension, { extension: 'tsx' }
  it_behaves_like SupportedExtension, { extension: 'css' }
  it_behaves_like SupportedExtension, { extension: 'js.map' }
  it_behaves_like SupportedExtension, { extension: 'mjs.map' }
  it_behaves_like SupportedExtension, { extension: 'jsx.map' }
  it_behaves_like SupportedExtension, { extension: 'ts.map' }
  it_behaves_like SupportedExtension, { extension: 'tsx.map' }
  it_behaves_like SupportedExtension, { extension: 'css.map' }

  it_behaves_like IncludedPath, { path: 'config/foo.js' }
  it_behaves_like IncludedPath, { path: 'app/views/foo.js' }
  it_behaves_like IncludedPath, { path: 'lib/foo.js' }
  it_behaves_like IncludedPath, { path: 'vendor/foo.js' }
  it_behaves_like IncludedPath, { path: 'node_modules/mypackage/index.js' }

  it 'raises on compilation error' do
    expect do
      get '/lib/includes_error.js'
    end.to raise_exception(Proscenium::Builder::BuildError)
  end

  with 'unsupported path' do
    let(:app) { subject.new HelloApp }

    it 'passes through' do
      get '/db/some.js'
      expect(response.body).to be == 'Hello, World!'
    end
  end

  with 'vendored engine with package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem1/lib/gem1/gem1.js'

      expect(response.body).to include 'console.log("gem1");'
    end
  end

  with 'vendored engine without package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem3/lib/gem3/gem3.js'

      expect(response.body).to include 'console.log("gem3");'
    end
  end

  with 'un-vendored engine with package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem2/lib/gem2/gem2.js'

      expect(response.body).to include 'console.log("gem2");'
    end
  end

  with 'un-vendored engine without package.json' do
    it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
      get '/gem4/lib/gem4/gem4.js'

      expect(response.body).to include 'console.log("gem4");'
    end
  end

  it 'serves javascript' do
    get '/lib/foo.js'

    expect(response.headers['Content-Type']).to be == 'application/javascript'
    expect(response.body.squish).to include %(
      console.log("/lib/foo.js");
      //# sourceMappingURL=foo.js.map
    ).squish
  end

  it 'serves javascript source map' do
    get '/lib/foo.js.map'

    expect(response.headers['Content-Type']).to be == 'application/json'
    expect(response.body).to include %("sources": ["../../../lib/foo.js"])
  end

  it 'serves css' do
    get '/lib/foo.css'

    expect(response.body.squish).to include %(
      .body { color: red; }
      /*# sourceMappingURL=foo.css.map */
    ).squish
  end

  it 'serves css source map' do
    get '/lib/foo.css.map'

    expect(response.headers['Content-Type']).to be == 'application/json'
    expect(response.body).to include %("sources": ["../../../lib/foo.css"])
  end

  it 'serves css module' do
    get '/lib/styles.module.css'

    expect(response.headers['Content-Type']).to be == 'text/css'
    expect(response.body.squish).to include %(
      .myClass-330940eb { color: pink; }
      /*# sourceMappingURL=styles.module.css.map */
    ).squish
  end

  it 'serves @proscenium/* runtime libs' do
    get '/@proscenium/test.js'

    expect(response.body).to include('console.log("/@proscenium/test.js")')
  end

  it 'serves proscenium/ui/* ui' do
    get '/proscenium/ui/test.js'

    expect(response.body).to include('console.log("/proscenium/ui/test.js")')
  end

  with 'cache_query_string' do
    it 'should set cache header ' do
      Proscenium.config.cache_query_string = 'v1'
      get '/lib/query_cache.js'

      expect(response.headers['Cache-Control']).to be == 'public, max-age=2592000'
    end

    it 'should propogate cache_query_string' do
      skip 'TODO'

      Proscenium.config.cache_query_string = 'v1'
      get '/lib/query_cache.js?v1'

      expect(response.body).to include 'console.log("/lib/query_cache.js")'
    end
  end

  private

  def get(path)
    @response = Rack::MockRequest.new(app).request('GET', path)
  end
end
