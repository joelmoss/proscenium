# frozen_string_literal: true

require 'test_helper'

class Proscenium::UI::Form::Fields::TelTest < ActiveSupport::TestCase
  extend ViewHelper

  let(:subject) { Proscenium::UI::Form }
  let(:user) { User.new name: 'Joel Moss' }
  view -> { subject.new(user) } do |f|
    f.tel_field :phone
  end

  it 'has a select input' do
    assert view.has_css?('pui-tel-field select > option:first-child[value="AF"]')
  end

  it 'has a text input' do
    assert view.has_css?('pui-tel-field input[type="text"][name="user[phone]"]')
  end

  it 'country defaults to US' do
    assert view.has_css?('pui-tel-field select>option[selected="selected"][value="US"]')
  end

  with ':default_country' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.tel_field :phone, default_country: :gb
    end

    it 'country == GB' do
      assert view.has_css?('pui-tel-field select>option[selected="selected"][value="GB"]')
    end
  end
end
