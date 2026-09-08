# frozen_string_literal: true

module Proscenium
  class Middleware
    class Vendor
      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)
        pathname = Pathname.new(request.path)

        return @app.call(env) unless pathname.fnmatch?(VENDOR_PATH_GLOB, File::FNM_EXTGLOB)

        # The prefix strip is an argument to the file lookup, not a rewrite of the request. It used
        # to assign `request.path_info`, which writes `env['PATH_INFO']` - the same hash handed to
        # `@app.call` on a miss - so `/vendor/lib/foo.js` with nothing under `vendor/` continued
        # down the stack as `/lib/foo.js`, matched `APP_PATH_GLOB`, and was built and served from
        # the app root under the URL the client had actually asked for.
        ActionDispatch::FileHandler.new(
          Rails.root.join('vendor').to_s,
          headers: {
            'X-Proscenium-Middleware' => 'vendor',
            'Cache-Control' => "public, max-age=#{100.years}, immutable"
          }
        ).attempt(env.merge('PATH_INFO' => request.path.delete_prefix('/vendor'))) || @app.call(env)
      end
    end
  end
end
