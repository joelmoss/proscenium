# frozen_string_literal: true

module Proscenium
  module Middleware
    # Serves static files from disk that end with .js or .css.
    class Static < Base
      def attempt
        benchmark :static do
          Rack::File.new(root, { 'X-Proscenium-Middleware' => 'static' }).call(@request.env)
        end
      end
    end
  end
end
