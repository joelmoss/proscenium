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

        request.path_info = request.path.delete_prefix('/vendor')

        ActionDispatch::FileHandler.new(
          Rails.root.join('vendor').to_s,
          headers: {
            'X-Proscenium-Middleware' => 'vendor',
            'Cache-Control' => "public, max-age=#{100.years}, immutable"
          }
        ).attempt(request.env) || @app.call(env)
      end
    end
  end
end
