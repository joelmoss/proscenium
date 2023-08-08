# frozen_string_literal: true

require 'view_component'

class Proscenium::ViewComponent < ViewComponent::Base
  extend ActiveSupport::Autoload

  autoload :Sideload
  autoload :TagBuilder
  autoload :ReactComponent
  autoload :CssModules

  include Proscenium::SourcePath
  include CssModules

  # Side loads the class, and its super classes that respond to `.source_path`.
  #
  # Assign the `abstract_class` class variable to any abstract class, and it will not be side
  # loaded. Additionally, if the class instance responds to `sideload?`, and it returns false, it
  # will not be side loaded.
  module Sideload
    def before_render
      Proscenium::SideLoad.sideload_inheritance_chain self

      super
    end
  end

  class << self
    attr_accessor :abstract_class

    def inherited(child)
      child.prepend Sideload

      super
    end
  end
end
