# frozen_string_literal: true

class User < ApplicationRecord
  has_many :taggings
  has_many :tags, through: :taggings
  has_many :events
  has_one :address

  enum :gender, %i[male female other], suffix: true
  enum :gender_with_db_default, %i[male female other], suffix: true
  enum :gender_with_code_default, %i[male female other], default: :female, suffix: true

  def to_s
    name
  end
end
