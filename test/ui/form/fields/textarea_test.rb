# frozen_string_literal: true

require 'test_helper'

class Proscenium::UI::Form::Fields::TextareaTest < ActiveSupport::TestCase
  extend ViewHelper

  let(:subject) { Proscenium::UI::Form }
  let(:user) { User.new name: 'Joel Moss' }
  view -> { subject.new(user) } do |f|
    f.textarea_field :name
  end

  it 'side loads the form and date css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    assert_equal ['/proscenium/ui/form.css'], imports
  end

  it 'has a label' do
    assert_match %r{^<div><span>Name</span></div>}, view.find('label').native.inner_html
  end

  it 'has a textarea with value' do
    assert_equal 'Joel Moss', view.find('textarea').text
  end
end
