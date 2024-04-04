# frozen_string_literal: true

class Author < User
  accepts_nested_attributes_for :address, :events
end
