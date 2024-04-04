# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class Textarea < Base
    def template
      field do
        label do
          attrs = build_attributes
          value = attrs.delete(:value)
          textarea(name: field_name, **attrs) { value }
        end
        hint
      end
    end
  end
end
