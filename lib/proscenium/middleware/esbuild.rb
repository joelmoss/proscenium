# frozen_string_literal: true

module Proscenium
  class Middleware
    class Esbuild < Base
      class CompileError < Base::CompileError
        def initialize(args)
          detail = args[:detail]
          detail = ActiveSupport::HashWithIndifferentAccess.new(Oj.load(detail, mode: :strict))
          args[:detail] = "#{detail[:text]} in #{detail[:location][:file]}:" +
                          detail[:location][:line].to_s

          super args
        end
      end

      def attempt
        benchmark :esbuild do
          render_response build([
            "#{cli} --root #{root}",
            cache_query_string,
            "--lightningcss-bin #{lightningcss_cli} #{path}"
          ].compact.join(' '))
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

      def lightningcss_cli
        if ENV['PROSCENIUM_TEST']
          'bin/lightningcss'
        else
          Gem.bin_path 'proscenium', 'lightningcss'
        end
      end

      def cache_query_string
        q = Proscenium.config.cache_query_string
        q ? "--cache-query-string #{q}" : nil
      end
    end
  end
end
