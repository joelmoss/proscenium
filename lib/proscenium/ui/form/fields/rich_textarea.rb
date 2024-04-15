# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class RichTextarea < Base
    register_element :trix_editor

    def view_template
      value = attributes.delete(:value)

      field do
        label
        trix_editor input: field_id
        hint
        form.hidden_field(*attribute, id: field_id, value: value&.to_trix_html)
      end
    end
  end
end
