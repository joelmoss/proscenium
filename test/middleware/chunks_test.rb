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
