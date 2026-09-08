# frozen_string_literal: true

module Proscenium
  class Middleware
    class Chunks
      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        # The path has to yield a content hash as well as match the prefix. `CHUNKS_PATH` only
        # checks the prefix, so extracting the hash below used to be free to assume a shape the
        # guard never looked at - and `/_asset_chunks/nohash.js`, which any client can ask for,
        # indexed the nil match and returned a 500 from here. Parsed once, by the guard that
        # decides whether this middleware owns the request at all.
        return @app.call(env) unless request.path.match?(CHUNKS_PATH) &&
                                     (etag = request.path[/-\$([a-z0-9]+)\$/i, 1])

        ActionDispatch::FileHandler.new(
          Proscenium.config.output_path.to_s,
          headers: {
            'X-Proscenium-Middleware' => 'chunks',
            'SourceMap' => "#{request.path}.map",
            'Cache-Control' => "public, max-age=#{100.years}, immutable",
            'ETag' => etag
          }
        ).attempt(request.env) || @app.call(env)
      end
    end
  end
end
