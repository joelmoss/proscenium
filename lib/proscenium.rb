# frozen_string_literal: true

# require_relative 'proscenium/version'
require 'active_support/dependencies/autoload'

module Proscenium
  extend ActiveSupport::Autoload

  autoload :Middleware
  autoload :Builder
end

require 'proscenium/railtie'
