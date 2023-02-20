# frozen_string_literal: true

module Proscenium
  class Esbuild
    class CompileError < StandardError; end

    def self.build(...)
      new(...).build
    end

    def initialize(path, root:)
      @path = path
      @root = root
    end

    def build
      stdout, stderr, status = Open3.capture3(command)

      raise CompileError, stderr if !status.success? || !stderr.empty?

      stdout
    end

    private

    def command
      [
        cli,
        "--root #{@root}",
        "--lightningcss-bin #{lightningcss_bin}",
        cache_query_string,
        css_mixin_paths,
        @path
      ].compact.join(' ')
    end

    def cli
      if ENV['PROSCENIUM_TEST']
        'deno run -q -A lib/proscenium/compilers/esbuild.js'
      else
        ::Gem.bin_path 'proscenium', 'esbuild'
      end
    end

    def lightningcss_bin
      ENV['PROSCENIUM_TEST'] ? 'bin/lightningcss' : ::Gem.bin_path('proscenium', 'lightningcss')
    end

    def css_mixin_paths
      Proscenium.config.css_mixin_paths.map do |mpath|
        "--css-mixin-path #{mpath}"
      end.join ' '
    end

    def cache_query_string
      q = Proscenium.config.cache_query_string
      q ? "--cache-query-string #{q}" : nil
    end
  end
end
