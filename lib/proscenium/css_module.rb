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

  autoload :Transformer

  # Accepts one or more CSS class names, and transforms them into CSS module names.
  #
  # @param name [String,Symbol,Array<String,Symbol>]
  def css_module(*names)
    cssm.class_names(*names, require_prefix: false).join ' '
  end

  private

  def cssm
    @cssm ||= Transformer.new(source_path)
  end
end
