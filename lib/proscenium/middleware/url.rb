# frozen_string_literal: true

module Proscenium
  class Middleware
    # Handles requests prefixed with "url:https://"; downloading, caching, and compiling them.
    class Url < Esbuild
      private

      # @override [Esbuild] It's a URL, so always assume it is renderable (we won't actually know
      #   until it's downloaded).
      def renderable?
        true
      end

      # @override [Esbuild]
      def path_to_build
        CGI.unescape(@request.path)[1..]
      end
    end
  end
end
