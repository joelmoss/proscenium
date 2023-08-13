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
    get "/#{args[:path]}/foo.js"

    expect(response.status).to be == 200
  end
end

describe Proscenium::Middleware do
  attr_reader :response

  def before
    Proscenium.config.include_paths = Set.new(Proscenium::APPLICATION_INCLUDE_PATHS)
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

  it_behaves_like IncludedPath, { path: 'config' }
  it_behaves_like IncludedPath, { path: 'app/assets' }
  it_behaves_like IncludedPath, { path: 'app/views' }
  it_behaves_like IncludedPath, { path: 'lib' }
  it_behaves_like IncludedPath, { path: 'node_modules' }

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

  with 'include_paths << "db"' do
    it 'works' do
      Proscenium.config.include_paths << 'db'

      get '/db/some.js'
      expect(response.body).to include('console.log("/db/some.js")')
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

  it 'serves js from url' do
    get '/https%3A%2F%2Fga.jspm.io%2Fnpm%3Ais-fn%403.0.0%2Findex.js'

    expect(response.headers['Content-Type']).to be == 'application/javascript'
    expect(response.body.squish).to include %(// url:https://ga.jspm.io/npm:is-fn@3.0.0/index.js)
  end

  it 'serves js sourcemap' do
    get '/https%3A%2F%2Fga.jspm.io%2Fnpm%3Ais-fn%403.0.0%2Findex.js.map'

    expect(response.headers['Content-Type']).to be == 'application/json'
    expect(response.body.squish).to include %(sources": ["url:https://ga.jspm.io/npm:is-fn@3.0.0/index.js"])
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
