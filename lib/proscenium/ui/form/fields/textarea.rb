# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class Textarea < Base
    register_element :pui_textarea

    def view_template
      field :pui_textarea do
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
