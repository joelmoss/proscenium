# frozen_string_literal: true

module Proscenium::Phlex::ResolveCssModules
  def _build_attributes(attributes, buffer:)
    attributes.tap do |attrs|
      if attrs.key?(:class)
        attrs[:class] = tokens(attrs[:class])

        if attrs[:class].include?('@')
          attrs[:class] = attrs[:class].split.map do |cls|
            cls.starts_with?('@') ? cssm.class_names!(cls[1..]) : cls
          end.join ' '
        end
      end
    end

    super(attributes, buffer: buffer)
  end
end
