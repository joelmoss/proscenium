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
          render_response build("#{cli} --root #{root} #{path}")
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
          [
            'deno run -q --import-map import_map.json -A', 'lib/proscenium/compilers/esbuild.js'
          ].join(' ')
        else
          Gem.bin_path 'proscenium', 'esbuild'
        end
      end
    end
  end
end
