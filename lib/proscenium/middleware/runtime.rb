# frozen_string_literal: true

module Proscenium
  class Middleware
    class Runtime < Esbuild
      private

      def real_path
        @real_path ||= Pathname.new(@request.path.sub(%r{^/@proscenium},
                                                      '/lib/proscenium/libs')).to_s
      end

      def root
        @root ||= Proscenium::Railtie.root.to_s
      end
    end
  end
end
