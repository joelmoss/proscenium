# frozen_string_literal: true

require 'view_component'

class Proscenium::ViewComponent < ViewComponent::Base
  extend ActiveSupport::Autoload

  autoload :Sideload
  autoload :ReactComponent
  autoload :CssModules

  include Proscenium::SourcePath
  include CssModules

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
