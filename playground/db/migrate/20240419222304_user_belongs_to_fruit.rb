# frozen_string_literal: true

class UserBelongsToFruit < ActiveRecord::Migration[7.1]
  def change
    add_reference :users, :fruit, foreign_key: true
  end
end
