# frozen_string_literal: true

require 'view_helper'

Field = Sus::Shared('field') do |args|
  type = args[:type]
  input_type = type.to_s.dasherize

  let(:user) { User.new }

  view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
    f.send :"#{type}_field", :name
  end

  it 'side loads only the form css modules' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/ui/form/component.module.css']
  end

  it "has a #{type} field" do
    expect(view.has_field?('user[name]', type: input_type)).to be == true
  end

  it 'has a label' do
    expect(view.find('label').text).to be == 'Name'
  end

  it 'renders label before input' do
    expect(view.find('label').native.inner_html).to be =~ %r{^<div><span>Name</span>}
  end

  with 'attribute name as a string' do
    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", 'foo[]'
    end

    it 'pass the name through as is' do
      expect(view.has_field?('foo[]', type: input_type)).to be == true
    end
  end

  with ':label' do
    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :name, label: 'Foobar'
    end

    it 'overrides label' do
      expect(view.find('label').text).to be == 'Foobar'
    end
  end

  with ':class' do
    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :name, class: :my_class
    end

    it 'appends class value to field wrapper' do
      expect(view.find('div[class^="field_wrapper-"]')[:class]).to(
        be == 'field_wrapper-fe0d823b my_class'
      )
    end
  end

  with 'label: false' do
    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :name, label: false
    end

    it 'omits label' do
      expect(view.find('label').text).to be(:empty?)
    end
  end

  with 'model error' do
    let(:user) do
      User.new.tap do |u|
        u.errors.add :name, :invalid
      end
    end

    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :name
    end

    it 'has data-field-error on wrapping div' do
      expect(view.find('.field_wrapper-fe0d823b')['data-field-error']).not.to be_nil
    end

    it 'shows error message' do
      expect(view.find('label').text).to be == 'Nameis invalid'
    end
  end

  with 'error option as ActiveModel::Error' do
    let(:user) do
      User.new.tap do |u|
        u.errors.add :name, :invalid
      end
    end

    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :name, error: f.model.errors.where(:name).first
    end

    it 'shows error message' do
      expect(view.find('label>div>span:last-child').text).to be == 'is invalid'
    end
  end

  with 'error option as String' do
    let(:user) do
      User.new.tap do |u|
        u.errors.add :name, :invalid
      end
    end

    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :name, error: 'is foobar'
    end

    it 'shows error message' do
      expect(view.find('label>div>span:last-child').text).to be == 'is foobar'
    end
  end

  with 'nested one-to-one attributes' do
    let(:user) do
      User.new address: Address.new(city: 'Chorley')
    end

    view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
      f.send :"#{type}_field", :address, :city
    end

    it 'translates label' do
      expect(view.find('label').text).to be == 'City'
    end

    it 'has a nested field' do
      expect(view.has_field?('user[address][city]', type: input_type)).to be == true
    end
  end

  with 'accepts_nested_attributes_for' do
    let(:author) do
      Author.new address: Address.new(city: 'Chorley')
    end

    view -> { Proscenium::UI::Form::Component.new(author, action: '/') } do |f|
      f.send :"#{type}_field", :address, :city
    end

    it 'translates label' do
      expect(view.find('label').text).to be == 'City'
    end

    it 'has a nested field' do
      expect(view.has_field?('author[address_attributes][city]', type: input_type)).to be == true
    end
  end

  describe 'bang attributes' do
    with ':required!' do
      view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
        f.send :"#{type}_field", :name, :required!
      end

      it 'adds required attribute to input' do
        expect(view.find_field('Name', type: input_type)[:required]).to be == ''
      end
    end

    with 'required: true' do
      view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
        f.send :"#{type}_field", :name, required: true
      end

      it 'adds required attribute to input' do
        expect(view.find_field('Name', type: input_type)[:required]).to be == ''
      end
    end

    with ':required! and required: false' do
      view -> { Proscenium::UI::Form::Component.new(user, action: '/') } do |f|
        f.send :"#{type}_field", :name, :required!, required: false
      end

      it 'expects required to be false' do
        expect(view.find_field('Name', type: input_type)[:required]).to be_nil
      end
    end
  end
end

describe Proscenium::UI::Form::Component do
  describe 'basic inputs' do
    include TestHelper
    extend ViewHelper

    describe '#text_field' do
      it_behaves_like Field, { type: :text }
    end

    describe '#url_field' do
      it_behaves_like Field, { type: :url }
    end

    describe '#time_field' do
      it_behaves_like Field, { type: :time }
    end

    describe '#week_field' do
      it_behaves_like Field, { type: :week }
    end

    describe '#month_field' do
      it_behaves_like Field, { type: :month }
    end

    describe '#email_field' do
      it_behaves_like Field, { type: :email }
    end

    describe '#color_field' do
      it_behaves_like Field, { type: :color }
    end

    describe '#search_field' do
      it_behaves_like Field, { type: :search }
    end

    describe '#password_field' do
      it_behaves_like Field, { type: :password }
    end

    describe '#hidden_field' do
      let(:user) { User.new }
      view -> { Proscenium::UI::Form::Component.new(user, url: '/') } do |f|
        f.hidden_field :name
      end

      it 'has a hidden field' do
        expect(view.has_field?('user[name]', type: :hidden)).to be == true
      end

      it 'has no label' do
        expect(view.has_css?('label')).to be == false
      end

      with 'value from model' do
        let(:user) { User.new name: 'Joel Moss' }

        it 'has a value' do
          expect(view.has_field?('user[name]', type: :hidden, with: 'Joel Moss')).to be == true
        end
      end
    end
  end
end
