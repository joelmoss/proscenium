# frozen_string_literal: true

require 'active_support'

module Proscenium
  extend ActiveSupport::Autoload

  # Default paths for Rails assets. Used by the `compute_asset_path` helper to maintain Rails
  # default conventions of where JS and CSS files are located.
  DEFAULT_RAILS_ASSET_PATHS = {
    stylesheet: 'app/assets/stylesheets/',
    javascript: 'app/javascript/'
  }.freeze

  FILE_EXTENSIONS = ['js', 'mjs', 'ts', 'jsx', 'tsx', 'css', 'js.map', 'mjs.map', 'jsx.map',
                     'ts.map', 'tsx.map', 'css.map'].freeze
  ALLOWED_DIRECTORIES = 'app,lib,config,vendor,node_modules'
  APP_PATH_GLOB = "/{#{ALLOWED_DIRECTORIES}}/**.{#{FILE_EXTENSIONS.join(',')}}".freeze
  GEMS_PATH_GLOB = "/node_modules/@rubygems/**.{#{FILE_EXTENSIONS.join(',')}}".freeze
  CHUNKS_PATH = %r{^/_asset_chunks/}

  # Environment variables that should always be passed to the builder.
  DEFAULT_ENV_VARS = Set['RAILS_ENV', 'NODE_ENV'].freeze

  autoload :SourcePath
  autoload :Utils
  autoload :Monkey
  autoload :Middleware
  autoload :Manifest
  autoload :EnsureLoaded
  autoload :SideLoad
  autoload :CssModule
  autoload :ReactComponentable
  autoload :Helper
  autoload :Builder
  autoload :Importer
  autoload :Resolver
  autoload :BundledGems

  class Deprecator
    def deprecation_warning(name, message, _caller_backtrace = nil)
      msg = "`#{name}` is deprecated and will be removed in a near future release of Proscenium"
      msg << " (#{message})" if message
      Kernel.warn msg
    end
  end

  class Error < StandardError; end

  class MissingAssetError < Error
    def initialize(path)
      super
      @path = path
    end

    def message
      "The asset '#{@path}' was not found."
    end
  end

  class PathResolutionFailed < Error
    def initialize(path)
      @path = path
      super
    end

    def message
      "Path #{@path.inspect} cannot be resolved"
    end
  end

  class << self
    def config
      @config ||= Railtie.config.proscenium
    end

    def root
      Railtie.root
    end
  end
end

require 'proscenium/railtie'
