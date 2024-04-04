# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Form::Fields::RichTextarea do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new name: 'Joel Moss' }
  view -> { Proscenium::UI::Form::Component.new(user) } do |f|
    f.rich_textarea_field :name
  end

  it 'side loads the form and date css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/ui/form/component.module.css',
                              '/proscenium/ui/form/fields/rich_textarea.js',
                              '/proscenium/ui/form/fields/rich_textarea.css']
  end

  it 'has a label' do
    expect(view.find('label').text).to be == 'Name'
  end

  it 'has a trix-editor element' do
    expect(view.has_css?('trix-editor[input=user_name]')).to be_truthy
  end

  it 'has a hidden input' do
    name = 'user[name]'
    expect(view.has_field?(name, type: :hidden)).to be == true
    expect(view.find_field(name, type: :hidden).value).to be == 'Joel Moss'
  end
end
