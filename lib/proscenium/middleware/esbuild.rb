# frozen_string_literal: true

module Proscenium
  class Middleware
    class Esbuild < Base
      def attempt
        benchmark :esbuild do
          render_response build("#{cli} --root #{root} #{path}")
        end
      end

      private

      def path
        @request.path[1..]
      end

      def cli
        if ENV['PROSCENIUM_TEST']
          'deno run -q --import-map import_map.json -A lib/proscenium/compilers/esbuild.js'
        else
          Gem.bin_path 'proscenium', 'esbuild'
        end
      end
    end
  end
end
