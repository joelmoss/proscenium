# frozen_string_literal: true

module Proscenium
  class SideLoad
    extend ActiveSupport::Autoload

    NotIncludedError = Class.new(StandardError)

    autoload :Monkey
    autoload :Helper
    autoload :EnsureLoaded

    EXTENSIONS = %i[js css].freeze
    EXTENSION_MAP = {
      '.module.css' => :css,
      '.css' => :css,
      '.tsx' => :js,
      '.ts' => :js,
      '.jsx' => :js,
      '.js' => :js
    }.freeze

    attr_reader :path

    class << self
      # Append the given `path`.
      #
      # @return [Array] appended URL paths
      def append(path, extension_map = EXTENSION_MAP)
        new(path, extension_map).append
      end

      # Side load the given `path` at `type`, without first resolving the path.
      #
      # @param path [String]
      # @param type [Symbol] :js or :css
      def append!(path, _type)
        Proscenium::Importer.import path, sideloaded: true
      end

      def log(value)
        ActiveSupport::Notifications.instrument('sideload.proscenium', identifier: value)

        value
      end
    end

    # @param path [Pathname, String] The path of the Ruby file to be side loaded.
    # @param extension_map [Hash] File extensions to side load.
    def initialize(path, extension_map = EXTENSION_MAP)
      @path = (path.is_a?(Pathname) ? path : Rails.root.join(path)).sub_ext('')
      @extension_map = extension_map
    end

    def append
      @extension_map.filter_map do |ext, _type|
        next unless (resolved_path = resolve_path(path.sub_ext(ext)))

        Proscenium::Importer.import resolved_path, sideloaded: true

        resolved_path
      end
    end

    private

    def log(...)
      self.class.log(...)
    end

    # @param path [Pathname]
    # @return [String,Nil] the resolved path, or nil if the path cannot be resolved.
    def resolve_path(path)
      path.exist? ? Utils.resolve_path(path.to_s) : nil
    end
  end
end
