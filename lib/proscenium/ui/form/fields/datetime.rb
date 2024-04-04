# frozen_string_literal: true

module Proscenium::UI::Form::Fields
  class Datetime < Input
    def field_type
      'datetime-local'
    end

    private

    def value
      super&.strftime('%Y-%m-%dT%H:%M')
    end
  end
end
