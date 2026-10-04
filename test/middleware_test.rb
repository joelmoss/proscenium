# frozen_string_literal: true

require 'test_helper'

DummyApp = ->(_) { [404, {}, []] }
HelloApp = ->(_) { [200, { 'Content-Type' => 'text/plain' }, ['Hello, World!']] }

class Proscenium::MiddlewareTest < ActiveSupport::TestCase
  attr_reader :response

  before do
    Proscenium.config.bundle = true
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

  ['config/foo.js', 'app/views/foo.js', 'lib/foo.js', 'node_modules/pkg/index.js'].each do |path|
    it "serves from #{path}" do
      get "/#{path}"

      assert_equal 200, response.status
    end
  end

  # #154: a copy a linker nested under a gem's dependency context is served like node_modules.
  describe 'a package nested under a dependency context' do
    before do
      @dir = Rails.root.join('.proscenium')
      FileUtils.mkdir_p(@dir.join('packages/widget/node_modules/ms'))
      File.write(@dir.join('packages/widget/node_modules/ms/index.js'), 'export default "ms"')
      File.write(@dir.join('packages/widget/package.json'), '{}')
    end

    after { FileUtils.rm_rf(@dir) }

    it 'serves it, and not the context itself or Proscenium state' do
      get '/.proscenium/packages/widget/node_modules/ms/index.js'

      assert_equal 200, response.status
      assert_includes response.body, '"ms"'

      %w[/.proscenium/packages/widget/package.json /.proscenium/lock].each do |path|
        get path

        assert_equal 404, response.status
      end
    end
  end

  it 'raises on compilation error' do
    assert_raises Proscenium::Builder::BuildError do
      get '/lib/includes_error.js'
    end
  end

  context 'unsupported/unknown path' do
    let(:app) { subject.new HelloApp }

    it 'passes through' do
      get '/lib/some.js'

      assert_equal 'Hello, World!', response.body
    end
  end

  context '@rubygems/*' do
    it 'builds local with package.json' do
      get '/node_modules/@rubygems/gem1/lib/gem1/gem1.js'

      assert_includes response.body, 'console.log("gem1");'
    end

    it 'builds local without package.json' do
      get '/node_modules/@rubygems/gem3/lib/gem3/gem3.js'

      assert_includes response.body, 'console.log("gem3");'
    end

    # focus
    # it 'builds from pnpm link' do
    #   get '/node_modules/@rubygems/gem2/styles.module.css'

    #   assert_includes response.body, '.myClass-330940eb { color: pink; }'
    # end

    context 'un-vendored gem with package.json' do
      it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
        get '/node_modules/@rubygems/gem2/lib/gem2/gem2.js'

        assert_includes response.body, 'console.log("gem2");'
      end
    end

    context 'un-vendored gem without package.json' do
      it 'serves assets from allowed dirs at /[GEM_NAME]/*' do
        get '/node_modules/@rubygems/gem4/lib/gem4/gem4.js'

        assert_includes response.body, 'console.log("gem4");'
      end
    end

    # A gem that is not in the Gemfile used to raise out of the readability probe and 500,
    # where the same shape of miss under an app path passes through (see 'unsupported/unknown
    # path' above, and the assertion below that the two now agree).
    context 'gem not in the Gemfile' do
      let(:app) { subject.new HelloApp }

      it 'passes through' do
        get '/node_modules/@rubygems/notagem/lib/x.js'

        assert_equal 'Hello, World!', response.body
      end

      it 'passes through the same way a missing app file does' do
        get '/lib/not_on_disk.js'
        missing_app_file = response.status

        get '/node_modules/@rubygems/notagem/lib/x.js'

        assert_equal missing_app_file, response.status
      end
    end
  end

  # `find_type` matched the allowed-directory glob against the request verbatim, while the
  # readability probe normalised and `path_to_build` did not - so one request was routed by a
  # directory it does not resolve to, approved against one file, and built as a third. Every one
  # of these served 200 before the paths were normalised once, up front.
  context 'a path that normalises out of its own directory' do
    let(:app) { subject.new HelloApp }

    it 'does not serve a file outside the allowed directories' do
      secret = Rails.root.join('public', 'normalise_probe.js')
      secret.write 'console.log("outside");'

      get '/lib/../public/normalise_probe.js'

      assert_equal 'Hello, World!', response.body
    ensure
      secret.delete if secret.exist?
    end

    it 'does not serve a file beside a gem root' do
      beside = Rails.root.join('vendor', 'index.js')
      beside.write 'console.log("beside gem1");'

      get '/node_modules/@rubygems/gem1/../index.js'

      assert_equal 'Hello, World!', response.body
    ensure
      beside.delete if beside.exist?
    end

    # Decoded once by `normalise_path` for routing and building, then a second time by the
    # readability probe, so `%252e%252e` was built as a literal `%2e%2e` segment but probed as
    # `..`. The probe approved a file at the root, the build then failed on the literal name, and
    # the difference between that error and a fall-through told a client the file existed.
    it 'does not probe a double-encoded path as a different file' do
      probe = Rails.root.join('double_decode_probe.js')
      probe.write 'console.log("root");'

      get '/lib/%252e%252e/double_decode_probe.js'

      assert_equal 'Hello, World!', response.body
    ensure
      probe.delete if probe.exist?
    end

    # The other half of the same mismatch: a file whose name holds a literal `%` is what the
    # builder is asked for, so it is what the probe has to find.
    it 'serves a file whose name holds a literal percent sign' do
      literal = Rails.root.join('lib', 'a%20b.js')
      literal.write 'console.log("literal");'

      get '/lib/a%2520b.js'

      assert_equal 200, response.status
      assert_includes response.body, 'console.log("literal");'
    ensure
      literal.delete if literal.exist?
    end

    it 'passes a path Rack rejects straight through' do
      env = Rack::MockRequest.env_for('/lib/foo.js')
      env['PATH_INFO'] = "/lib/foo.js\0"

      status, _headers, body = subject.new(HelloApp).call(env)

      assert_equal 200, status
      assert_equal ['Hello, World!'], body
    end
  end

  # The readability probe decoded the path before checking the disk, and the builder was handed
  # the request verbatim, so this was approved against `mixin.css` and then failed on the literal
  # `%6dixin.css` - a 500 out of the middleware for a URL any client can send.
  it 'serves a percent-encoded gem path' do
    get '/node_modules/@rubygems/gem1/%6dixin.css'

    assert_equal 200, response.status
    assert_includes response.body, 'vendor/gem1/mixin.css'
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

  describe 'css modules' do
    test 'from app' do
      get '/lib/styles.module.css'

      assert_equal 'text/css', response.headers['Content-Type']
      assert_match Regexp.new(".myClass_#{CSS_MODULE_DIGEST} \\{"),
                   response.body
    end

    test 'from external gem' do
      get '/node_modules/@rubygems/gem2/styles.module.css'

      assert_equal 'text/css', response.headers['Content-Type']
      assert_match Regexp.new(".myClass_#{CSS_MODULE_DIGEST} \\{"),
                   response.body
    end

    test 'from vendored gem' do
      get '/node_modules/@rubygems/gem1/styles.module.css'

      assert_equal 'text/css', response.headers['Content-Type']
      assert_match Regexp.new(".myClass_#{CSS_MODULE_DIGEST} \\{"),
                   response.body
    end
  end

  private

  def get(path)
    @response = Rack::MockRequest.new(app).request('GET', path)
  end
end
