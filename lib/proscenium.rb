# frozen_string_literal: true

require 'active_support/dependencies/autoload'

module Proscenium
  extend ActiveSupport::Autoload

  autoload :Current
  autoload :Middleware
  autoload :SideLoad
  autoload :CssModule
  autoload :ViewComponent
  autoload :Helper
end

require 'proscenium/railtie'
