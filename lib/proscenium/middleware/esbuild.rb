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
            "--lightningcss-bin #{lightningcss_cli} #{path_to_build}"
          ].compact.join(' '))
        end
      end

      private

      # @override [Esbuild] Support paths prefixed with '/ruby_gems/' by rewriting the root to be
      # the the path of the gem.
      def renderable?
        if ruby_gem?
          gem_name = path_to_build.split(File::SEPARATOR)[1]
          @root = Pathname.new(Bundler.rubygems.loaded_specs(gem_name).full_gem_path)
          @request.path_info = @request.path_info.delete_prefix("/ruby_gems/#{gem_name}")
        end

        super
      end

      # @return [String] the path to the file which will be built.
      def path_to_build
        @request.path[1..]
      end

      def sourcemap?
        @request.path.ends_with?('.map')
      end

      def ruby_gem?
        @request.path.starts_with?('/ruby_gems/')
      end

      def cli
        if ENV['PROSCENIUM_TEST']
          'deno run -q --import-map import_map.json -A lib/proscenium/compilers/esbuild.js'
        else
          Gem.bin_path 'proscenium', 'esbuild'
        end
      end

      def lightningcss_cli
        ENV['PROSCENIUM_TEST'] ? 'bin/lightningcss' : Gem.bin_path('proscenium', 'lightningcss')
      end

      def cache_query_string
        q = Proscenium.config.cache_query_string
        q ? "--cache-query-string #{q}" : nil
      end
    end
  end
end
