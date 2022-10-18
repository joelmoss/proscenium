# frozen_string_literal: true

module Proscenium
  class Middleware
    # Provides a way to render files outside of the Rails root during non-production. This is
    # primarily to support linked NPM modules, for example when using `pnpm link ...`.
    class OutsideRoot < Esbuild
      private

      # @override [Esbuild] reassigns root to '/'.
      def renderable?
        old_root = root
        @root = Pathname.new('/')

        super
      ensure
        @root = old_root
      end

      # @override [Esbuild] does not remove leading slash, ensuring it is an absolute path.
      def path
        @request.path
      end
    end
  end
end
