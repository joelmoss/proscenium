# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Form::Fields::Checkbox do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new }
  view -> { Proscenium::UI::Form::Component.new(user) } do |f|
    f.checkbox_field :active
  end

  it 'side loads only the form css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/ui/form/component.module.css']
  end

  it 'has an unchecked checkbox input' do
    expect(view.has_field?('user[active]', type: :checkbox,
                                           checked: false)).to be == true
  end

  it 'has a hidden input with the falsey value' do
    expect(view.find_field('user[active]', type: :hidden)[:value]).to be == '0'
  end

  it 'is checked' do
    user.active = true

    expect(view.has_field?('user[active]', type: :checkbox,
                                           checked: true)).to be == true
  end

  it 'renders label after input' do
    expect(view.find('label').native.to_html).to be == %(
      <label><input name="user[active]" type="hidden" value="0"><input name="user[active]" type="checkbox" value="1"><div><span>Active</span></div></label>
    ).strip
  end

  with ':label' do
    view -> { Proscenium::UI::Form::Component.new(user) } do |f|
      f.checkbox_field :active, label: 'Foobar'
    end

    it 'overrides label' do
      expect(view.find('label').text).to be == 'Foobar'
    end
  end

  with 'predicate? method' do
    view -> { Proscenium::UI::Form::Component.new(user) } do |f|
      f.checkbox_field :active?
    end

    it 'overrides label' do
      user.active = true

      expect(view.find('label').text).to be == 'Active?'
      expect(view.has_field?('user[active]', type: :checkbox,
                                             checked: true)).to be == true
    end
  end
end
