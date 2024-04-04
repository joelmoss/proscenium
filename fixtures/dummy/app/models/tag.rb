# frozen_string_literal: true

class Tag < ActiveRecord::Base
  belongs_to :user, optional: true
  def to_s
    name
  end
end
