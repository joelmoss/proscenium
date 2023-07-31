# frozen_string_literal: true

require 'active_support/dependencies/autoload'

module Proscenium
  extend ActiveSupport::Autoload

  autoload :Utils
  autoload :Middleware
  autoload :SideLoad
  autoload :CssModule
  autoload :ReactComponentable
  autoload :ViewComponent
  autoload :Phlex
  autoload :Helper
  autoload :Builder
  autoload :Importer

  class PathResolutionFailed < StandardError
    def initialize(path)
      @path = path
      super
    end

    def message
      "Path #{@path.inspect} cannot be resolved"
    end
  end
end

require 'proscenium/railtie'
