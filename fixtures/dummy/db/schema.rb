# frozen_string_literal: true

ActiveRecord::Schema[7.1].define(version: 20_231_114_174_857) do
  create_table 'events', force: :cascade do |t|
    t.string :name
    t.bigint 'user_id'
    t.index ['user_id'], name: 'index_events_on_user_id'
  end

  create_table 'taggings', force: :cascade do |t|
    t.bigint 'tag_id'
    t.bigint 'user_id'
    t.index ['tag_id'], name: 'index_taggings_on_tag_id'
    t.index ['user_id'], name: 'index_taggings_on_user_id'
  end

  create_table 'tags', force: :cascade do |t|
    t.string 'name'
  end

  create_table 'addresses', force: :cascade do |t|
    t.string 'city'
    t.string 'postcode'
    t.bigint 'user_id'
    t.date :registered_at
    t.index ['user_id'], name: 'index_addresses_on_user_id'
  end

  create_table 'users', force: :cascade do |t|
    t.string 'role'
    t.string 'name'
    t.string 'type'
    t.boolean 'active', default: false, null: false
    t.integer 'age'
    t.integer 'gender'
    t.integer 'gender_with_db_default', default: 0
    t.integer 'gender_with_code_default'
  end
end
