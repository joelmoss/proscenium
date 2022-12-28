# frozen_string_literal: true

require 'view_component'

class Proscenium::ViewComponent < ViewComponent::Base
  extend ActiveSupport::Autoload
  include Proscenium::CssModule

  autoload :TagBuilder
  autoload :ReactComponent

  # Side loads the class, and its super classes that respond to `.path`. Assign the `abstract_class`
  # class variable to any abstract class, and it will not be side loaded.
  module Sideload
    def before_render
      klass = self.class
      while !klass.abstract_class && klass.respond_to?(:path) && klass.path
        Proscenium::SideLoad.append klass.path
        klass = klass.superclass
      end

      super
    end
  end

  class << self
    attr_accessor :path, :abstract_class

    def inherited(child)
      child.path = if caller_locations(1, 1).first.label == 'inherited'
                     Pathname.new caller_locations(2, 1).first.path
                   else
                     Pathname.new caller_locations(1, 1).first.path
                   end

      child.prepend Sideload if Rails.application.config.proscenium.side_load

      super
    end
  end

  # @override Auto compilation of class names to css modules.
  def render_in(...)
    cssm.compile_class_names(super(...))
  end

  private

  # Overrides ActionView::Helpers::TagHelper::TagBuilder, allowing us to intercept the
  # `css_module` option from the HTML options argument of the `tag` and `content_tag` helpers, and
  # prepend it to the HTML `class` attribute.
  def tag_builder
    @tag_builder ||= Proscenium::ViewComponent::TagBuilder.new(self)
  end
end
