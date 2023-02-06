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

    # Forcefully side load the given `path` at `type`.
    def self.append!(path, type)
      return if Proscenium::Current.loaded[type].include?(path)

      Proscenium::Current.loaded[type] << path
      Proscenium.logger.debug "Side loaded #{path}"
    end

    # @param path [Pathname, String] The path of the file to be side loaded.
    # @param extensions [Array] File extensions to side load (default: DEFAULT_EXTENSIONS)
    def initialize(path, extension_map = EXTENSION_MAP)
      @path = (path.is_a?(Pathname) ? path : Rails.root.join(path)).sub_ext('')
      @extension_map = extension_map

      Proscenium::Current.loaded ||= EXTENSIONS.index_with { |_e| Set.new }
    end

    def append
      root, relative_path, path_to_load = Proscenium::Utils.path_pieces(path)

      @extension_map.map do |ext, type|
        path_with_ext = "#{relative_path}#{ext}"
        url_with_ext = "#{path_to_load}#{ext}"

        # Make sure path is not already side loaded, and actually exists.
        if !Proscenium::Current.loaded[type].include?(url_with_ext) &&
           Pathname.new(root).join(path_with_ext).exist?
          Proscenium::Current.loaded[type] << log(url_with_ext)
        end

        url_with_ext
      end
    end

    private

    def log(value)
      Proscenium.logger.debug "Side loaded #{value}"
      value
    end
  end
end
