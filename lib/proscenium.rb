# frozen_string_literal: true

# require 'zeitwerk'

# loader = Zeitwerk::Loader.for_gem
# loader.inflector.inflect 'ui' => 'UI'
# loader.ignore "#{__dir__}/proscenium/ext"
# loader.ignore "#{__dir__}/proscenium/libs"
# loader.setup

module Proscenium
  extend ActiveSupport::Autoload

  FILE_EXTENSIONS = ['js', 'mjs', 'ts', 'jsx', 'tsx', 'css', 'js.map', 'mjs.map', 'jsx.map',
                     'ts.map', 'tsx.map', 'css.map'].freeze

  # Default paths for Rails assets. Used by the `compute_asset_path` helper to maintain Rails
  # default conventions of where JS and CSS files are located.
  DEFAULT_RAILS_ASSET_PATHS = {
    stylesheet: 'app/assets/stylesheets/',
    javascript: 'app/javascript/'
  }.freeze

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
  autoload :BundledGems
  autoload :RubyGems
  autoload :Registry
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

    def ui_path
      @ui_path ||= Railtie.root.join('lib', 'proscenium', 'ui')
    end

    def ui_path_regex
      @ui_path_regex ||= Regexp.new("^#{Proscenium.ui_path}/")
    end

    def root
      Railtie.root
    end
  end
end

require 'proscenium/railtie'
