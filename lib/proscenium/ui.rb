# frozen_string_literal: true

require 'dry-types'

module Proscenium::UI
  extend ActiveSupport::Autoload

  autoload :Component
  autoload :Breadcrumbs

  module Types
    include Dry.Types()
  end
end
