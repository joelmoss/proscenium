# frozen_string_literal: true

module Proscenium::UI::Form
  extend ActiveSupport::Autoload

  autoload :Component
  autoload :FieldMethods
  autoload :Translation

  module Fields
    extend ActiveSupport::Autoload

    autoload :Base
    autoload :Input
    autoload :Hidden
    autoload :RadioInput
    autoload :Checkbox
    autoload :Textarea
    autoload :RichTextarea
    autoload :RadioGroup
    autoload :Select
    autoload :Phone
  end
end
