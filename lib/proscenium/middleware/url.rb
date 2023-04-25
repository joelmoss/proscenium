# frozen_string_literal: true

module Proscenium
  class Middleware
    # Handles requests for URL encoded URL's; downloading, caching, and compiling them.
    class Url < Esbuild
      private

      # @override [Esbuild] It's a URL, so always assume it is renderable (we won't actually know
      #   until it's downloaded).
      def renderable?
        true
      end
    end
  end
end
