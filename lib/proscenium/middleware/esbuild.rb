# frozen_string_literal: true

module Proscenium
  class Middleware
    class Esbuild < Base
      class CompileError < Base::CompileError
        def initialize(args)
          detail = args[:detail]
          detail = ActiveSupport::HashWithIndifferentAccess.new(Oj.load(detail, mode: :strict))

          args[:detail] = if detail[:location]
                            "#{detail[:text]} in #{detail[:location][:file]}:" +
                              detail[:location][:line].to_s
                          else
                            detail[:text]
                          end

          super args
        end
      end

      def attempt
        benchmark :esbuild do
          render_response build([
            "#{cli} --root #{root}",
            cache_query_string,
            css_mixin_paths,
            # (ruby_gem? && import_map? ? "--import-map #{import_map_path}" : nil),
            "--lightningcss-bin #{lightningcss_cli} #{path_to_build}"
          ].compact.join(' '))
        end
      end

      private

      def import_map?
        !import_map_path.nil?
      end

      def import_map_path
        if (js_map = Rails.root.join('config', 'import_map.js')).exist?
          js_map
        elsif (json_map = Rails.root.join('config', 'import_map.json')).exist?
          json_map
        end
      end

      def css_mixin_paths
        Proscenium.config.css_mixin_paths.map do |mpath|
          "--css-mixin-path #{mpath}"
        end.join ' '
      end

      def cli
        if ENV['PROSCENIUM_TEST']
          'deno run -q --import-map import_map.json -A lib/proscenium/compilers/esbuild.js'
        else
          ::Gem.bin_path 'proscenium', 'esbuild'
        end
      end

      def lightningcss_cli
        ENV['PROSCENIUM_TEST'] ? 'bin/lightningcss' : ::Gem.bin_path('proscenium', 'lightningcss')
      end

      def cache_query_string
        q = Proscenium.config.cache_query_string
        q ? "--cache-query-string #{q}" : nil
      end
    end
  end
end
