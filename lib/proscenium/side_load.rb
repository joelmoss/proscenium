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
      @extension_map.map do |ext, type|
        next unless (resolved_path = resolve_path(path, ext))

        # Make sure path is not already side loaded.
        unless Proscenium::Current.loaded[type].include?(resolved_path)
          Proscenium::Current.loaded[type] << log(resolved_path)
        end

        resolved_path
      end
    end

    private

    # Resolve the given absolute file system `path` and `ext` to a URL path.
    def resolve_path(path, ext) # rubocop:disable Metrics/AbcSize
      path = path.sub_ext(ext)

      # First check that path exists on the file system.
      return unless path.exist?

      path = path.to_s

      matched_gem = Proscenium.config.side_load_gems.find do |_, opts|
        path.starts_with?("#{opts[:root]}/")
      end

      if matched_gem
        sroot = "#{matched_gem[1][:root]}/"
        relpath = path.delete_prefix(sroot)

        if matched_gem[1][:package_name]
          return Esbuild::Golib.resolve("#{matched_gem[1][:package_name]}/#{relpath}")
        end

        # TODO: manually resolve the path without esbuild
        raise "Path #{path} cannot be found in app or gems"
      end

      sroot = "#{Rails.root}/"
      return path.delete_prefix(sroot) if path.starts_with?(sroot)

      raise "Path #{path} cannot be found in app or gems"
    end

    def log(value)
      Proscenium.logger.debug "Side loaded #{value}"
      value
    end
  end
end
