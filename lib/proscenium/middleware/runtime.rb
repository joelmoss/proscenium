# frozen_string_literal: true

module Proscenium
  class Middleware
    class Runtime < Esbuild
      private

      def renderable?
        old_root = root
        old_path_info = @request.path_info

        @root = Pathname.new(__dir__).join('../')
        @request.path_info = @request.path_info.sub(%r{^/proscenium-runtime/}, 'runtime/')

        super
      ensure
        @request.path_info = old_path_info
        @root = old_root
      end
    end
  end
end
