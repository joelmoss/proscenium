# frozen_string_literal: true

module Proscenium
  class Middleware
    class Chunks
      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        # Decode and clean the path BEFORE deciding anything about it, then hand that same path
        # to the file handler. `ActionDispatch::FileHandler` normalises `PATH_INFO` itself before
        # it resolves a file, so a guard reading the raw path is not looking at the path that
        # gets served: `/_asset_chunks/x-$FAKE$/%2e%2e/real-$ABC123$.js` passed both checks and
        # then served `real-$ABC123$.js` tagged `FAKE`, and `x-$FAKE$/../../lib/foo.js` left the
        # chunk directory altogether, since the handler's root is the whole output directory.
        # Both under `immutable, max-age=100.years`, so a wrong ETag is not something a client
        # can clear.
        #
        # The path also has to yield a content hash, not just match the prefix - `CHUNKS_PATH`
        # checks only the latter, and `/_asset_chunks/nohash.js` used to index the nil match and
        # return a 500 from here.
        return @app.call(env) unless (path = cleaned_path(request.path)) &&
                                     path.match?(CHUNKS_PATH) &&
                                     (etag = path[/-\$([a-z0-9]+)\$/i, 1])

        ActionDispatch::FileHandler.new(
          Proscenium.config.output_path.to_s,
          headers: {
            'X-Proscenium-Middleware' => 'chunks',
            'SourceMap' => "#{path}.map",
            'Cache-Control' => "public, max-age=#{100.years}, immutable",
            'ETag' => etag
          }
        ).attempt(env.merge('PATH_INFO' => path)) || @app.call(env)
      end

      private

      # The request path as the file handler will see it: percent-decoded, with `.` and `..`
      # segments resolved. Nil for a path Rack rejects outright. Mirrors `Base#clean_path`,
      # which does the same two Rack calls for the same reason.
      def cleaned_path(path)
        unescaped = Rack::Utils.unescape_path(path.chomp('/').delete_prefix('/'))
        return unless Rack::Utils.valid_path?(unescaped)

        "/#{Rack::Utils.clean_path_info(unescaped)}"
      end
    end
  end
end
