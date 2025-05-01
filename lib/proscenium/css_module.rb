# frozen_string_literal: true

module Proscenium::CssModule
  extend ActiveSupport::Autoload

  autoload :Path
  autoload :Transformer
  autoload :Rewriter

  class TransformError < StandardError
    def initialize(name, additional_msg = nil)
      msg = "Failed to transform CSS module `#{name}`"
      msg << ' - ' << additional_msg if additional_msg

      super(msg)
    end
  end

  module ClassMethods
    def css_module(*names, path: nil)
      path ||= respond_to?(:css_module_path) ? css_module_path : path

      cssm = Transformer.new(path)
      cssm.class_names(*names, require_prefix: false).map { |name, _| name }.join(' ')
    end

    def class_names(*names, path: nil)
      path ||= respond_to?(:css_module_path) ? css_module_path : path
      names = names.flatten.compact

      cssm = Transformer.new(path)
      cssm.class_names(*names).map { |name, _| name }.join(' ') unless names.empty?
    end
  end

  def self.included(base)
    base.extend ClassMethods
  end

  # Accepts one or more CSS class names, and transforms them into CSS module names.
  #
  # @param name [String,Symbol,Array<String,Symbol>]
  # @param path [Pathname] the path to the CSS module file to use for the transformation.
  # @return [String] the transformed CSS module names concatenated as a string.
  def css_module(*names, path: nil)
    transformer = path.nil? ? cssm : Transformer.new(path)
    transformer.class_names(*names, require_prefix: false).map { |name, _| name }.join(' ')
  end

  # @param name [String,Symbol,Array<String,Symbol>]
  # @param path [Pathname] the path to the CSS file to use for the transformation.
  # @return [String] the transformed CSS module names concatenated as a string.
  def class_names(*names, path: nil)
    names = names.flatten.compact
    transformer = path.nil? ? cssm : Transformer.new(path)
    transformer.class_names(*names).map { |name, _| name }.join(' ') unless names.empty?
  end

  private

  def cssm
    @cssm ||= Transformer.new(self.class.css_module_path)
  end
end
