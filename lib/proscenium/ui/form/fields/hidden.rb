# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class Hidden < Base
    def view_template
      input(name: field_name, type: :hidden, **build_attributes)
    end
  end
end
