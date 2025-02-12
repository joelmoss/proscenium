# frozen_string_literal: true

class User < ApplicationRecord
  belongs_to :fruit
  enum :gender, %i[male female other]
  validates :name, presence: true
end
