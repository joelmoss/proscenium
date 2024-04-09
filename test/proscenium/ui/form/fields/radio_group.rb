# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Form::Fields::RadioGroup do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new }

  with 'options as last argument' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.radio_group :role, %i[admin manager]
    end

    it 'renders a radio input for each provided value' do
      values = view.all('input[type="radio"][name="user[role]"]').map(&:value)
      expect(values).to be == %w[admin manager]
    end
  end

  with ':options attribute' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.radio_group :role, options: %i[admin manager]
    end

    it 'renders a radio input for each provided value' do
      values = view.all('input[type="radio"][name="user[role]"]').map(&:value)
      expect(values).to be == %w[admin manager]
    end
  end

  with 'selected value' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.radio_group :role, %i[admin manager]
    end

    it 'is checked' do
      user.role = :manager

      field = view.find_field('user[role]', checked: true)
      expect(field[:value]).to be == 'manager'
    end
  end

  with 'enum attribute' do
    view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
      f.radio_group :gender
    end

    it 'uses enum values for options' do
      fields = view.all('label:has(input[type="radio"][name="user[gender]"])')
      expect(fields.map(&:text)).to be == %w[GenderMale GenderFemale GenderOther]

      fields = view.all('label > input[type="radio"][name="user[gender]"]')
      expect(fields.map(&:value)).to be == %w[male female other]
    end

    with 'persisted value' do
      let(:user) { User.new gender: :male }

      it 'uses persisted value' do
        field = view.find_field('user[gender]', checked: true)
        expect(field.value).to be == 'male'
      end
    end

    with 'default value' do
      view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
        f.radio_group :gender_with_db_default
        f.radio_group :gender_with_code_default
      end

      it 'uses default enum value' do
        field = view.find_field('user[gender_with_db_default]', checked: true)
        expect(field.value).to be == 'male'

        field = view.find_field('user[gender_with_code_default]', checked: true)
        expect(field.value).to be == 'female'
      end
    end
  end

  with 'belongs_to association attribute' do
    def before
      super
      User.create! [{ name: 'Joel Moss' }, { name: 'Eve Moss' }]
    end

    let(:event) { Event.new }
    view -> { Proscenium::UI::Form.new(event) } do |f|
      f.radio_group :user
    end

    it 'uses association values for options' do
      fields = view.all('label:has(input[type="radio"][name="event[user_id]"])')
      expect(fields.map(&:text)).to be == ['UserJoel Moss', 'UserEve Moss']

      fields = view.all('label > input[type="radio"][name="event[user_id]"]')
      expect(fields.map(&:value)).to be == User.pluck(:id).map(&:to_s)
    end

    it 'has none checked' do
      expect(view.has_field?('event[user]', checked: true)).to be_falsey
    end

    with 'persisted value' do
      let(:event) { Event.new user: User.first }

      it 'uses persisted value' do
        field = view.find_field('event[user_id]', checked: true)
        expect(field.value).to be == event.user.id.to_s
      end
    end
  end
end
