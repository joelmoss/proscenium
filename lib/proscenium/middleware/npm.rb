# frozen_string_literal: true

module Proscenium
  class Middleware
    # Handles requests prefixed with "npm:".
    #
    # If a path starts with any path found in `config.include_ruby_gems`, then we treat it as
    # from a ruby gem, and use it's NPM package by prefixing the URL path with "npm:".
    class Npm < Esbuild
      private

      # @override [Esbuild] It's an NPM package, so always assume it is renderable.
      def renderable?
        true
      end
    end
  end
end
