# frozen_string_literal: true

require 'test_helper'

class Proscenium::UI::Form::Fields::RadioInputTest < ActiveSupport::TestCase
  extend ViewHelper

  let(:subject) { Proscenium::UI::Form }
  let(:user) { User.new }

  view -> { subject.new(user) } do |f|
    f.radio_field :role, value: :admin
  end

  it 'side loads only the form css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    assert_equal ['/node_modules/@rubygems/proscenium/form.css'], imports
  end

  it 'has a radio input with the provided value' do
    assert_equal 'admin', view.find_field('user[role]', type: :radio)[:value]
  end

  it 'is checked' do
    user.role = :admin

    assert view.has_field?('user[role]', checked: true)
  end

  it 'has a label with the value' do
    assert_equal 'Admin', view.find('label>span').text
  end

  with 'label attribute' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.radio_field :role, value: :admin, label: 'Administrator'
    end

    it 'has a label with the value' do
      assert_equal 'Administrator', view.find('label>span').text
    end
  end
end
