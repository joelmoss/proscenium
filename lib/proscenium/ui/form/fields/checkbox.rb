# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  # Renders a checkbox field similar to how Rails handles it.
  #
  # A predicate attribute name can be given:
  #
  #   checkbox_field :active?
  #
  class Checkbox < Base
    register_element :pui_checkbox

    def view_template
      checked = ActiveModel::Type::Boolean.new.cast(value.nil? ? false : value)

      checked_value = attributes.delete(:checked_value) || '1'
      unchecked_value = attributes.delete(:unchecked_value) || '0'

      # TODO: use component
      # render Proscenium::UI::Fields::Checkbox::Component.new field_name, checked:

      field :pui_checkbox do
        label do |content|
          input(name: field_name, type: :hidden, value: unchecked_value, **attributes)
          input(name: field_name, type: :checkbox, value: checked_value, checked:, **attributes)
          yield_content_with_no_args { content }
        end
        hint
      end
    end
  end
end
