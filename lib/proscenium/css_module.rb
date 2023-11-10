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
  # @return [String] the transformed CSS module names concatenated as a string.
  def css_module(*names)
    cssm.class_names(*names, require_prefix: false).map { |name, _| name }.join(' ')
  end

  # @param name [String,Symbol,Array<String,Symbol>]
  # @return [String] the transformed CSS module names concatenated as a string.
  def class_names(*names)
    names = names.flatten.compact
    cssm.class_names(*names).map { |name, _| name }.join(' ') unless names.empty?
  end

  private

  def cssm
    @cssm ||= Transformer.new(self.class.css_module_path)
  end
end
