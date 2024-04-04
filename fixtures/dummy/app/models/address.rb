# frozen_string_literal: true

class Address < ActiveRecord::Base
  belongs_to :user
end
