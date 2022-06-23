# frozen_string_literal: true

module Proscenium
  module Middleware
    # Serves static files from disk that end with .js or .css. It's the default middleware.
    class Static < Base
      def attempt
        benchmark :static do
          Rack::File.new(root, { 'X-Proscenium-Middleware' => 'static' }).call(@request.env)
        end
      end

      private

      def renderable?
        /\.(js|css)$/i.match?(@request.path_info) && file_readable?
      end
    end
  end
end
