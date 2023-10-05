# frozen_string_literal: true

module Proscenium::CssModule
  extend ActiveSupport::Autoload

  autoload :Path
  autoload :Transformer

  class TransformError < StandardError
    def initialize(name, additional_msg = nil)
      msg = "Failed to transform CSS module `#{name}`"
      msg << ' - ' << additional_msg if additional_msg

      super msg
    end
  end

  # Accepts one or more CSS class names, and transforms them into CSS module names.
  #
  # @param name [String,Symbol,Array<String,Symbol>]
  def css_module(*names)
    cssm.class_names(*names, require_prefix: false).join ' '
  end

  private

  def cssm
    @cssm ||= Transformer.new(self.class.css_module_path)
  end
end
