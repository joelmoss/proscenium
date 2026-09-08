# frozen_string_literal: true

require 'test_helper'

# Chunks had no tests at all. These are the first, and two of them are the negative cases that
# used to 500: the middleware's guard checks only the `/_asset_chunks/` prefix, while building the
# response headers assumed the finer `-$HASH$` shape as well.
class Proscenium::Middleware::ChunksTest < ActiveSupport::TestCase
  attr_reader :response

  # Answers with the path it was given, so a fall-through can be told apart from a 404 served by
  # the middleware itself.
  FellThroughApp = ->(env) { [404, {}, [env['PATH_INFO']]] }

  let(:app) { Proscenium::Middleware::Chunks.new FellThroughApp }

  it 'serves a chunk, with the content hash as its etag' do
    within_chunk 'foo-$ABC123$.js', 'console.log("chunk");' do
      get '/_asset_chunks/foo-$ABC123$.js'

      assert_equal 200, response.status
      assert_equal 'ABC123', response.headers['ETag']
      assert_equal 'chunks', response.headers['X-Proscenium-Middleware']
      assert_equal '/_asset_chunks/foo-$ABC123$.js.map', response.headers['SourceMap']
      assert_includes response.body, 'console.log("chunk");'
    end
  end

  it 'passes through a chunk path with no content hash' do
    get '/_asset_chunks/nohash.js'

    assert_equal 404, response.status
    assert_equal '/_asset_chunks/nohash.js', response.body
  end

  it 'passes through a hashed chunk path that is not on disk' do
    get '/_asset_chunks/missing-$ABC123$.js'

    assert_equal 404, response.status
    assert_equal '/_asset_chunks/missing-$ABC123$.js', response.body
  end

  # The guard used to read the raw path while FileHandler decoded and cleaned it afterwards, so
  # the hash it captured need not belong to the file that got served - and the request need not
  # stay inside the chunk directory, since the handler's root is the whole output path. Both
  # answers carried `immutable, max-age=100.years`, which a client cannot clear.
  context 'a path that normalises to something else' do
    it 'does not serve a chunk under a hash taken from a discarded segment' do
      within_chunk 'real-$ABC123$.js', 'REAL' do
        get '/_asset_chunks/fake-$FAKE$/%2e%2e/real-$ABC123$.js'

        assert_equal 200, response.status
        assert_equal 'ABC123', response.headers['ETag']
        assert_includes response.body, 'REAL'
      end
    end

    it 'does not serve a file outside the chunk directory' do
      outside = Proscenium.config.output_path.join('lib', 'outside-$L32XTY22$.js')
      outside.dirname.mkpath
      outside.write 'OUTSIDE'

      get '/_asset_chunks/fake-$FAKE$/../../lib/outside-$L32XTY22$.js'

      assert_equal 404, response.status
      assert_not_includes response.body, 'OUTSIDE'
    ensure
      outside.delete if outside.exist?
    end

    # Built by hand because Rack::MockRequest cannot parse a URI containing a null byte, so the
    # only way to reach the guard with one is to set PATH_INFO directly.
    it 'rejects a path Rack will not accept' do
      env = Rack::MockRequest.env_for('/_asset_chunks/real-$ABC123$.js')
      env['PATH_INFO'] = "/_asset_chunks/real-$ABC123$.js\0"

      status, = Proscenium::Middleware::Chunks.new(FellThroughApp).call(env)

      assert_equal 404, status
    end
  end

  it 'passes through any other path' do
    get '/lib/foo.js'

    assert_equal 404, response.status
    assert_equal '/lib/foo.js', response.body
  end

  private

  def get(path)
    @response = Rack::MockRequest.new(app).request('GET', path)
  end

  # Writes a chunk into the configured output path for the duration of the block. Not a checked-in
  # fixture because everything under there is build output, wiped by the test suites.
  def within_chunk(name, content)
    path = Proscenium.config.output_path.join('_asset_chunks', name)
    path.dirname.mkpath
    path.write content

    yield
  ensure
    path.delete if path.exist?
  end
end
