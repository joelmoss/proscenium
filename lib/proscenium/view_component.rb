# frozen_string_literal: true

class Proscenium::ViewComponent < ViewComponent::Base
  extend ActiveSupport::Autoload

  autoload :Sideload
  autoload :ReactComponent
  autoload :CssModules

  include Proscenium::SourcePath
  include CssModules

  module Sideload
    def before_render
      Proscenium::SideLoad.sideload_inheritance_chain self, controller.sideload_assets_options

      super
    end
  end

  class_attribute :sideload_assets_options

  class << self
    attr_accessor :abstract_class

    def inherited(child)
      child.prepend Sideload

      super
    end

    def sideload_assets(value)
      self.sideload_assets_options = value
    end
  end
end
