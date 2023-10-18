# frozen_string_literal: true

require 'active_support/dependencies/autoload'

module Proscenium
  extend ActiveSupport::Autoload

  FILE_EXTENSIONS = ['js', 'mjs', 'ts', 'jsx', 'tsx', 'css', 'js.map', 'mjs.map', 'jsx.map',
                     'ts.map', 'tsx.map', 'css.map'].freeze

  ALLOWED_DIRECTORIES = 'app,lib,config,vendor,node_modules'

  # Environment variables that should always be passed to the builder.
  DEFAULT_ENV_VARS = Set['RAILS_ENV', 'NODE_ENV'].freeze

  autoload :SourcePath
  autoload :Utils
  autoload :Monkey
  autoload :Middleware
  autoload :EnsureLoaded
  autoload :SideLoad
  autoload :CssModule
  autoload :ReactComponentable
  autoload :ViewComponent
  autoload :Phlex
  autoload :Helper
  autoload :Builder
  autoload :Importer
  autoload :Resolver
  autoload :UI

  class Deprecator
    def deprecation_warning(name, message, _caller_backtrace = nil)
      msg = "`#{name}` is deprecated and will be removed in a near future release of Proscenium"
      msg << " (#{message})" if message
      Kernel.warn msg
    end
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

  class << self
    def config
      @config ||= Railtie.config.proscenium
    end

    def cache
      @cache ||= config.cache || ActiveSupport::Cache::NullStore.new
    end
  end
end

require 'proscenium/railtie'
