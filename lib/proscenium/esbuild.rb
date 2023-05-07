# frozen_string_literal: true

module Proscenium
  class Esbuild
    class CompileError < StandardError; end

    extend ActiveSupport::Autoload

    autoload :Golib

    def self.build(...)
      new(...).build
    end

    def initialize(path, root:, base_url:)
      @path = path
      @root = root
      @base_url = base_url
    end

    def build
      Proscenium::Esbuild::Golib.new(root: @root, base_url: @base_url).build(@path, bundle: true)
    end

    private

    def cache_query_string
      q = Proscenium.config.cache_query_string
      q ? "--cache-query-string #{q}" : nil
    end
  end
end
