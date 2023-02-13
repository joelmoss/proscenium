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

  def self.logger
    @logger ||= Rails.logger.tagged('Proscenium')
  end

  def self.reset_current_side_loaded
    Current.loaded = SideLoad::EXTENSIONS.to_h { |e| [e, Set.new] }
  end

  module Utils
    module_function

    # @param value [#to_s] The value to create the digest from. This will usually be a `Pathname`.
    # @return [String] string digest of the given value.
    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    # Resolves the given CSS class names to CSS modules.
    #
    # @param names [String, Array]
    # @param hash: [String]
    # @returns [Array] of class names generated from the given CSS module `names` and `hash`.
    def class_names(*names, hash:)
      names.flatten.compact.map do |name|
        sname = name.to_s
        if sname.starts_with?('_')
          "_#{sname[1..].camelize(:lower)}#{hash}"
        else
          "#{sname.camelize(:lower)}#{hash}"
        end
      end
    end

    # Accepts a `path` to a file, and splits it into pieces:
    #   - The root file path
    #   - The file path relative to the root
    #   - The URL path relative to the application host
    #
    # If the `path` starts with any path found in `config.side_load_gems`, then we treat it as
    # from a ruby gem, and use it's NPM package by prefixing the URL path with "npm:".
    #
    # @param path [Pathname]
    # @return [Array] the root, relative path, and URL path.
    def path_pieces(path)
      spath = path.to_s

      matched_gem = Proscenium.config.side_load_gems.find do |_name, options|
        spath.starts_with?("#{options[:root]}/")
      end

      if matched_gem
        sroot = "#{matched_gem[1][:root]}/"
        relpath = spath.delete_prefix(sroot)

        urlpath = if matched_gem[1][:package_name]
                    "npm:#{matched_gem[1][:package_name]}"
                  else
                    "gem:#{matched_gem[0]}"
                  end

        return [sroot, relpath, "#{urlpath}/#{relpath}"]
      end

      sroot = "#{Rails.root}/"
      if spath.starts_with?(sroot)
        relpath = spath.delete_prefix(sroot)
        return [sroot, relpath, relpath]
      end

      raise "Path #{path} cannot be found in app or gems"
    end
  end
end

require 'proscenium/railtie'
