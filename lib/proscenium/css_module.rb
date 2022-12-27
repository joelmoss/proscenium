# frozen_string_literal: true

module Proscenium::CssModule
  extend ActiveSupport::Autoload

  autoload :Resolver

  # Like `css_modules`, but will raise if the stylesheet cannot be found.
  #
  # @param name [Array, String]
  def css_module!(names)
    cssm.class_names!(names).join ' '
  end

  # Accepts one or more CSS class names, and transforms them into CSS module names.
  #
  # @param name [Array, String]
  def css_module(names)
    cssm.class_names(names).join ' '
  end

  private

  def path
    self.class.path
  end

  def cssm
    @cssm ||= Resolver.new(path)
  end
end
