# frozen_string_literal: true

class Fruit < ApplicationRecord
  has_many :users
  def to_s = name
end
