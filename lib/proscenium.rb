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
end

require 'proscenium/railtie'
