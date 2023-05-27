# frozen_string_literal: true

module Proscenium::CssModule
  extend ActiveSupport::Autoload

  class StylesheetNotFound < StandardError
    def initialize(pathname)
      @pathname = pathname
      super
    end

    def message
      "Stylesheet is required, but does not exist: #{@pathname}"
    end
  end

  autoload :ClassNamesResolver
  autoload :Resolver # deprecated

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
