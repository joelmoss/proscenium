# frozen_string_literal: true

module Proscenium
  class Middleware
    # Handles requests for URL encoded URL's.
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
