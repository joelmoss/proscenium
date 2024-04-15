# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class Input < Base
    def view_template
      field do
        label do
          input(name: field_name, type: field_type, **build_attributes)
        end
        hint
      end
    end
  end
end
