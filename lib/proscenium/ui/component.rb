# frozen_string_literal: true

require 'dry-initializer'

module Proscenium::UI
  class Component < Proscenium::Phlex
    self.abstract_class = true

    extend Dry::Initializer
  end
end
