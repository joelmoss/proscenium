# frozen_string_literal: true

module Proscenium
  class Middleware
    class Runtime < Esbuild
      private

      def real_path
        @real_path ||= Pathname.new(@request.path.sub(%r{^/@proscenium},
                                                      '/lib/proscenium/libs')).to_s
      end

      def root_for_readable
        Proscenium::Railtie.root
      end
    end
  end
end
