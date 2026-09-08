# frozen_string_literal: true

require 'test_helper'

# Vendor had no tests at all. These are the first, and the misses are the cases that mattered: the
# middleware used to rewrite `env['PATH_INFO']` in place, and `env` is the same hash it hands to
# the app below it on a miss.
class Proscenium::Middleware::VendorTest < ActiveSupport::TestCase
  attr_reader :response

  # Reports the path it was called with, so a leaked rewrite is visible rather than merely implied.
  FellThroughApp = ->(env) { [404, {}, [env['PATH_INFO']]] }

  let(:app) { Proscenium::Middleware::Vendor.new FellThroughApp }

  it 'serves a vendored file' do
    get '/vendor/foo.js'

    assert_equal 200, response.status
    assert_equal 'vendor', response.headers['X-Proscenium-Middleware']
  end

  it 'passes a miss down the stack at the path the client asked for' do
    get '/vendor/lib/foo.js'

    assert_equal 404, response.status
    assert_equal '/vendor/lib/foo.js', response.body
  end

  it 'passes through a path it does not own' do
    get '/lib/foo.js'

    assert_equal 404, response.status
    assert_equal '/lib/foo.js', response.body
  end

  # The rewrite did not just mislabel the miss - `/lib/foo.js` exists in this app, so the request
  # went on to match `APP_PATH_GLOB` and was built and served from the app root, under the
  # `/vendor/...` URL. A miss in one middleware became a hit in another.
  context 'with the real middleware below it' do
    let(:app) { Proscenium::Middleware::Vendor.new Proscenium::Middleware.new(FellThroughApp) }

    it 'does not serve the app root file of the stripped path' do
      get '/vendor/lib/foo.js'

      assert_equal 404, response.status
      assert_nil response.headers['X-Proscenium-Middleware']
      assert_equal '/vendor/lib/foo.js', response.body
    end
  end

  private

  def get(path)
    @response = Rack::MockRequest.new(app).request('GET', path)
  end
end
