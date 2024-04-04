# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  # Renders a checkbox field similar to how Rails handles it.
  #
  # A predicate attribute name can be given:
  #
  #   checkbox_field :active?
  #
  class Checkbox < Base
    def template
      checked = ActiveModel::Type::Boolean.new.cast(value.nil? ? false : value)

      hint_content = attributes.delete(:hint)
      checked_value = attributes.delete(:checked_value) || '1'
      unchecked_value = attributes.delete(:unchecked_value) || '0'

      # TODO: use component
      # render Proscenium::UI::Fields::Checkbox::Component.new field_name, checked:

      field class: :@checkbox do
        label do |content|
          input(name: field_name, type: :hidden, value: unchecked_value, **attributes)
          input(name: field_name, type: :checkbox, value: checked_value, checked:,
                **attributes)
          plain content
        end

        hint hint_content
      end
    end
  end
end
