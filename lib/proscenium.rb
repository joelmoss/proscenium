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

  module Utils
    module_function

    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    # @param path [Pathname]
    # @return [Array] the root, relative path, and URL path.
    def path_pieces(path)
      spath = path.to_s

      matched_gem = Proscenium.config.include_ruby_gems.find do |_, root|
        spath.starts_with?("#{root}/")
      end

      if matched_gem
        sroot = "#{matched_gem[1]}/"
        relpath = spath.delete_prefix(sroot)
        return [sroot, relpath, "ruby_gems/#{matched_gem[0]}/#{relpath}"]
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
