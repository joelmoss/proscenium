# frozen_string_literal: true

require 'zeitwerk'
require 'proscenium/railtie'

loader = Zeitwerk::Loader.for_gem
loader.ignore "#{__dir__}/proscenium/core_ext/object/css_module_ivars.rb"
loader.setup

module Proscenium
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

    def root
      Railtie.root
    end
  end
end
