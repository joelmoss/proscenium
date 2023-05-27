# frozen_string_literal: true

module Proscenium
  class SideLoad
    extend ActiveSupport::Autoload

    autoload :Monkey

    EXTENSIONS = %i[js css].freeze
    EXTENSION_MAP = { '.css' => :css, '.js' => :js }.freeze

    attr_reader :path

    # Side load the given asset `path`, by appending it to `Proscenium::Current.loaded`, which is a
    # Set of 'js' and 'css' asset paths. This is idempotent, so side loading will never include
    # duplicates.
    #
    # @return [Array] appended URL paths
    def self.append(path, extension_map = EXTENSION_MAP)
      new(path, extension_map).append
    end

    # Side load the given `path` at `type`, without first resolving the path. This still respects
    # idempotency of `Proscenium::Current.loaded`.
    #
    # @param path [String]
    # @param type [Symbol] :js or :css
    def self.append!(path, type)
      return if Proscenium::Current.loaded[type].include?(path)

      Proscenium::Current.loaded[type] << path
      Proscenium.logger.debug "Side loaded #{path}"
    end

    # @param path [Pathname, String] The path of the file to be side loaded.
    # @param extension_map [Hash] File extensions to side load.
    def initialize(path, extension_map = EXTENSION_MAP)
      @path = (path.is_a?(Pathname) ? path : Rails.root.join(path)).sub_ext('')
      @extension_map = extension_map

      Proscenium::Current.loaded ||= EXTENSIONS.index_with { |_e| Set.new }
    end

    def append
      @extension_map.filter_map do |ext, type|
        next unless (resolved_path = resolve_path(path.sub_ext(ext)))

        # Make sure path is not already side loaded.
        unless Proscenium::Current.loaded[type].include?(resolved_path)
          Proscenium::Current.loaded[type] << log(resolved_path)
        end

        resolved_path
      end
    end

    private

    def resolve_path(path)
      path.exist? ? Utils.resolve_path(path.to_s) : nil
    end

    def log(value)
      Proscenium.logger.debug "Side loaded #{value}"
      value
    end
  end
end
