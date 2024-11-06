# frozen_string_literal: true

require 'test_helper'

class Proscenium::UI::Form::Fields::RadioGroupTest < ActiveSupport::TestCase
  extend ViewHelper

  let(:subject) { Proscenium::UI::Form }
  let(:user) { User.new }

  with 'options as last argument' do
    view -> { subject.new(user) } do |f|
      f.radio_group :role, %i[admin manager]
    end

    it 'renders a radio input for each provided value' do
      values = view.all('input[type="radio"][name="user[role]"]').map(&:value)
      assert_equal %w[admin manager], values
    end
  end

  with ':options attribute' do
    view -> { subject.new(user) } do |f|
      f.radio_group :role, options: %i[admin manager]
    end

    it 'renders a radio input for each provided value' do
      values = view.all('input[type="radio"][name="user[role]"]').map(&:value)
      assert_equal %w[admin manager], values
    end
  end

  with 'selected value' do
    view -> { subject.new(user) } do |f|
      f.radio_group :role, %i[admin manager]
    end

    it 'is checked' do
      user.role = :manager

      field = view.find_field('user[role]', checked: true)
      assert_equal 'manager', field[:value]
    end
  end

  with 'enum attribute' do
    view -> { subject.new(user, url: '/') } do |f|
      f.radio_group :gender
    end

    it 'uses enum values for options' do
      fields = view.all('label:has(input[type="radio"][name="user[gender]"])')
      assert_equal %w[Male Female Other], fields.map(&:text)

      fields = view.all('label > input[type="radio"][name="user[gender]"]')
      assert_equal %w[male female other], fields.map(&:value)
    end

    with 'persisted value' do
      let(:user) { User.new gender: :male }

      it 'uses persisted value' do
        field = view.find_field('user[gender]', checked: true)
        assert_equal 'male', field.value
      end
    end

    with 'default value' do
      view -> { subject.new(user, url: '/') } do |f|
        f.radio_group :gender_with_db_default
        f.radio_group :gender_with_code_default
      end

      it 'uses default enum value' do
        field = view.find_field('user[gender_with_db_default]', checked: true)
        assert_equal 'male', field.value

        field = view.find_field('user[gender_with_code_default]', checked: true)
        assert_equal 'female', field.value
      end
    end
  end

  with 'belongs_to association attribute' do
    before do
      User.create! [{ name: 'Joel Moss' }, { name: 'Eve Moss' }]
    end

    let(:event) { Event.new }
    view -> { subject.new(event) } do |f|
      f.radio_group :user
    end

    it 'uses association values for options' do
      fields = view.all('label:has(input[type="radio"][name="event[user_id]"])')
      assert_equal ['Joel Moss', 'Eve Moss'], fields.map(&:text)

      fields = view.all('label > input[type="radio"][name="event[user_id]"]')
      assert_equal User.pluck(:id).map(&:to_s), fields.map(&:value)
    end

    it 'has none checked' do
      assert_not view.has_field?('event[user]', checked: true)
    end

    with 'persisted value' do
      let(:event) { Event.new user: User.first }

      it 'uses persisted value' do
        field = view.find_field('event[user_id]', checked: true)
        assert_equal event.user.id.to_s, field.value
      end
    end
  end
end
