# frozen_string_literal: true

module Proscenium
  class Middleware
    class Esbuild < Base
      class CompileError < StandardError
        attr_reader :detail

        def initialize(detail)
          @detail = ActiveSupport::HashWithIndifferentAccess.new(Oj.load(detail, mode: :strict))

          super "#{@detail[:text]} in #{@detail[:location][:file]}:#{@detail[:location][:line]}"
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
      rescue CompileError => e
        render_response "export default #{e.detail.to_json}" do |response|
          response['X-Proscenium-Middleware'] = 'Esbuild::CompileError'
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
