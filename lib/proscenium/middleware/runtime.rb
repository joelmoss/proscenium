# frozen_string_literal: true

module Proscenium
  class Middleware
    class Runtime < Esbuild
      private

      def path
        @request.path
      end

      def renderable?
        @request.path_info = @request.path_info.sub(%r{^/proscenium-runtime/}, 'runtime/')
        super
      end

      def root
        @root ||= Pathname.new(__dir__).join('../')
      end
    end
  end
end
