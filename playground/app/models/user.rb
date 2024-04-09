# frozen_string_literal: true

class User < ApplicationRecord
  enum :gender, %i[male female other]
  validates :name, presence: true
end
