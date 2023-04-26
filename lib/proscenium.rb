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
  autoload :LinkToHelper
  autoload :Precompile
  autoload :Esbuild

  def self.logger
    @logger ||= Rails.logger.tagged('Proscenium')
  end

  def self.reset_current_side_loaded
    Current.reset
    Current.loaded = SideLoad::EXTENSIONS.to_h { |e| [e, Set.new] }
  end

  module Utils
    module_function

    # @param value [#to_s] The value to create the digest from. This will usually be a `Pathname`.
    # @return [String] string digest of the given value.
    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    def resolve(specifier)
      Esbuild::Golib.resolve specifier
    end

    # Resolve the given absolute file system `path` to a URL path.
    #
    # @param path [String]
    def resolve_path(path) # rubocop:disable Metrics/AbcSize
      raise ArgumentError, 'path must be a string' unless path.is_a?(String)

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

      return path.delete_prefix(Rails.root.to_s) if path.starts_with?("#{Rails.root}/")

      raise "Path #{path} cannot be found in app or gems"
    end

    # Resolves the given CSS class names to CSS modules.
    #
    # @param names [String, Array]
    # @param hash: [String]
    # @returns [Array] of class names generated from the given CSS module `names` and `hash`.
    def class_names(*names, hash: nil)
      names.flatten.compact.map do |name|
        sname = name.to_s
        if sname.starts_with?('_')
          "_#{sname[1..].camelize(:lower)}#{hash}"
        else
          "#{sname.camelize(:lower)}#{hash}"
        end
      end
    end
  end
end

require 'proscenium/railtie'
