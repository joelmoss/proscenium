# frozen_string_literal: true

require 'active_support/dependencies/autoload'

module Proscenium
  extend ActiveSupport::Autoload

  autoload :Current
  autoload :Middleware
  autoload :SideLoad
  autoload :CssModule
  autoload :ViewComponent
  autoload :Phlex
  autoload :Helper
  autoload :Builder

  def self.reset_current_side_loaded
    Current.reset
    Current.loaded = SideLoad::EXTENSIONS.to_h { |e| [e, Set.new] }
  end

  class PathResolutionFailed < StandardError
    def initialize(path)
      @path = path
      super
    end

    def message
      "Path #{@path.inspect} cannot be resolved"
    end
  end

  module Utils
    module_function

    # @param value [#to_s] The value to create the digest from. This will usually be a `Pathname`.
    # @return [String] string digest of the given value.
    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    # Resolve the given `path` to a URL path.
    #
    # @param path [String] Can be URL path, file system path, or bare specifier (ie. NPM package).
    # @return [String] URL path.
    def resolve_path(path) # rubocop:disable Metrics/AbcSize
      raise ArgumentError, 'path must be a string' unless path.is_a?(String)

      if path.starts_with?('./', '../')
        raise ArgumentError, 'path must be an absolute file system or URL path'
      end

      matched_gem = Proscenium.config.side_load_gems.find do |_, opts|
        path.starts_with?("#{opts[:root]}/")
      end

      if matched_gem
        sroot = "#{matched_gem[1][:root]}/"
        relpath = path.delete_prefix(sroot)

        if (package_name = matched_gem[1][:package_name] || matched_gem[0])
          return Builder.resolve("#{package_name}/#{relpath}")
        end

        # TODO: manually resolve the path without esbuild
        raise PathResolutionFailed, path
      end

      return path.delete_prefix(Rails.root.to_s) if path.starts_with?("#{Rails.root}/")

      Builder.resolve(path)
    end

    # Resolves CSS class `names` to CSS module names. Each name will be converted to a CSS module
    # name, consisting of the camelCased name (lower case first character), and suffixed with the
    # given `digest`.
    #
    # @param names [String, Array]
    # @param digest: [String]
    # @returns [Array] of class names generated from the given CSS module `names` and `digest`.
    def css_modularise_class_names(*names, digest: nil)
      names.flatten.compact.map { |name| css_modularise_class_name name, digest: digest }
    end

    def css_modularise_class_name(name, digest: nil)
      sname = name.to_s
      if sname.starts_with?('_')
        "_#{sname[1..].camelize(:lower)}#{digest}"
      else
        "#{sname.camelize(:lower)}#{digest}"
      end
    end
  end
end

require 'proscenium/railtie'
