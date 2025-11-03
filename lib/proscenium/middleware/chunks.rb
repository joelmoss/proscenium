# frozen_string_literal: true

module Proscenium
  class Middleware
    class Chunks
      def initialize(app)
        @app = app
      end

      def call(env)
        request = ActionDispatch::Request.new(env)

        return @app.call(env) unless request.path.match?(CHUNKS_PATH)

        ActionDispatch::FileHandler.new(
          Proscenium.config.output_path.to_s,
          headers: {
            'X-Proscenium-Middleware' => 'chunks',
            'Cache-Control' => "public, max-age=#{100.years}, immutable",
            'ETag' => request.path.match(/-\$([a-z0-9]+)\$/i)[1]
          }
        ).attempt(request.env) || @app.call(env)
      end
    end
  end
end
