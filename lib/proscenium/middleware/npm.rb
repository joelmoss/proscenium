# frozen_string_literal: true

module Proscenium
  class Middleware
    # Handles requests prefixed with "npm:", and returns the matching locally installed NPM package.
    class Npm < Esbuild
      private

      # @override [Esbuild] It's an NPM package, so always assume it is renderable.
      def renderable?
        true
      end
    end
  end
end
