# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class RadioInput < Base
    def view_template
      checked = attributes[:value].to_s == value.to_s

      default = model.class.human_attribute_name("#{attribute.join('.')}.#{attributes[:value]}")
      label_contents = attributes.delete(:label) || translate_label(default:)

      label do |_|
        input(name: field_name, type: :radio, checked:, **build_attributes)
        span { label_contents }
      end
    end
  end
end
