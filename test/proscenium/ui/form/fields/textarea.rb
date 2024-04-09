# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Form::Fields::Textarea do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new name: 'Joel Moss' }
  view -> { Proscenium::UI::Form.new(user) } do |f|
    f.textarea_field :name
  end

  it 'side loads the form and date css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/ui/form/component.module.css']
  end

  it 'has a label' do
    expect(view.find('label').native.inner_html).to be =~ %r{^<div><span>Name</span></div>}
  end

  it 'has a textarea with value' do
    expect(view.find('textarea').text).to be == 'Joel Moss'
  end
end
