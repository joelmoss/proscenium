# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Form::Fields::RadioInput do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new }

  view -> { Proscenium::UI::Form::Component.new(user) } do |f|
    f.radio_field :role, value: :admin
  end

  it 'side loads only the form css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/ui/form/component.module.css']
  end

  it 'has a radio input with the provided value' do
    expect(view.find_field('user[role]', type: :radio)[:value]).to be == 'admin'
  end

  it 'is checked' do
    user.role = :admin

    expect(view.has_field?('user[role]', checked: true)).to be == true
  end

  it 'has a label with the value' do
    expect(view.find('label>span').text).to be == 'Admin'
  end

  with 'label attribute' do
    view -> { Proscenium::UI::Form::Component.new(user) } do |f|
      f.radio_field :role, value: :admin, label: 'Administrator'
    end

    it 'has a label with the value' do
      expect(view.find('label>span').text).to be == 'Administrator'
    end
  end
end
