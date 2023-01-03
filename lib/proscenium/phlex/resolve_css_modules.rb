# frozen_string_literal: true

module Proscenium::Phlex::ResolveCssModules
  def _build_attributes(attributes, buffer:)
    attributes.tap do |attrs|
      attrs[:class] = resolve_css_modules(tokens(attrs[:class])) if attrs.key?(:class)
    end

    super(attributes, buffer: buffer)
  end

  private

  def resolve_css_modules(value)
    return value unless value.include?('@')

    value.split.map do |cls|
      cls.starts_with?('@') ? cssm.class_names!(cls[1..]) : cls
    end.join ' '
  end
end
