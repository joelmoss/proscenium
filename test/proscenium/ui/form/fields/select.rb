# frozen_string_literal: true

# require 'hue/testing/system'
require 'view_helper'

describe Proscenium::UI::Form::Fields::Select do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new }

  describe 'assets' do
    view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
      f.select_field :gender
    end

    it 'side loads the form and select css modules' do
      view
      imports = Proscenium::Importer.imported.keys

      expect(imports).to be == ['/proscenium/ui/form/component.module.css',
                                '/proscenium/ui/form/fields/select.jsx',
                                '/proscenium/ui/form/fields/select.module.css']
    end
  end

  with 'enum attribute' do
    view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
      f.select_field :gender
    end

    it 'uses enum values for options' do
      expect(view.has_select?('Gender', options: ['', 'Male', 'Female', 'Other'])).to be_truthy
    end

    with 'persisted value' do
      let(:user) { User.new gender: :male }

      it 'uses persisted value' do
        expect(view.has_select?('Gender', options: ['', 'Male', 'Female', 'Other'],
                                          selected: 'Male')).to be_truthy
      end
    end

    with 'default value' do
      view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
        f.select_field :gender_with_db_default
        f.select_field :gender_with_code_default
      end

      it 'uses default enum value' do
        expect(view.has_select?('Gender with db default', options: %w[Male Female Other],
                                                          selected: 'Male')).to be_truthy
        expect(view.has_select?('Gender with code default', options: %w[Male Female Other],
                                                            selected: 'Female')).to be_truthy
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
      f.select_field :user
    end

    it 'uses association values for options' do
      expect(view.has_select?('User', options: ['', 'Joel Moss', 'Eve Moss'])).to be_truthy
    end

    it 'has no value selected' do
      expect(view.has_select?('User', options: ['', 'Joel Moss', 'Eve Moss'],
                                      selected: nil)).to be_truthy
    end

    it 'has correct input name' do
      expect(view.find_field('User',
                             type: :select)[:name]).to be == 'event[user_id]'
    end

    with 'persisted value' do
      let(:event) { Event.new user: User.first }

      it 'uses persisted value' do
        expect(view.has_select?('User', options: ['', 'Joel Moss', 'Eve Moss'],
                                        selected: 'Joel Moss')).to be_truthy
      end
    end
  end

  with 'a block' do
    let(:form) do
      Class.new(Phlex::HTML) do
        def initialize(user) # rubocop:disable Lint/MissingSuper
          @user = user
        end

        def view_template
          render Proscenium::UI::Form.new(@user) do |f|
            f.select_field :gender do
              option { 'Bloke' }
              option { 'Chick' }
            end
          end
        end
      end
    end

    view -> { form.new user }

    it 'renders block in place of options' do
      expect(view.has_select?('user[gender]',
                              options: %w[Bloke Chick])).to be_truthy
    end
  end

  with 'options: Array<String>' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :tags, options: %w[1tag 2tag]
    end

    it 'uses given options' do
      options = view.find_css('option').map { |e| [e.text, e[:value]] }
      expect(options).to be == [%w[1tag 1tag], %w[2tag 2tag]]
    end
  end

  with 'options: Array<Array>' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :tags, options: [['Tag One', '1tag'], ['Tag two', '2tag']]
    end

    it 'uses given options' do
      options = view.find_css('option').map { |e| [e.text, e[:value]] }
      expect(options).to be == [['Tag One', '1tag'], ['Tag two', '2tag']]
    end
  end

  with 'options: Enumerable' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :tags, options: %w[1tag 2tag]
    end

    it 'uses given options' do
      expect(view.has_select?('user[tag_ids][]',
                              options: %w[1tag 2tag])).to be_truthy
    end
  end

  describe 'multiple values' do
    def before
      super
      Tag.create! [{ name: 'tag1' }, { name: 'tag2' }]
    end

    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :tags
    end

    it 'renders select of tags' do
      expect(view.has_select?('user[tag_ids][]', options: %w[tag1 tag2],
                                                 selected: nil)).to be_truthy
    end

    it 'defines :multiple attribute' do
      expect(view.find_field('Tags', type: :select)[:multiple]).to be(:present?)
    end

    with 'persisted value' do
      let(:user) do
        User.create! name: 'Joel Moss',
                     tags: Tag.where(name: 'tag1')
      end

      it 'selects persisted tags' do
        expect(view.has_select?('Tags', options: %w[tag1 tag2], selected: 'tag1')).to be_truthy
      end
    end
  end

  describe 'bang attributes' do
    with ':required!' do
      view -> { Proscenium::UI::Form.new(user) } do |f|
        f.select_field :gender, :required!
      end

      it 'adds required attribute to input' do
        expect(view.find_field('Gender', type: :select)[:required]).to be == ''
      end
    end

    with 'required: true' do
      view -> { Proscenium::UI::Form.new(user) } do |f|
        f.select_field :gender, required: true
      end

      it 'adds required attribute to input' do
        expect(view.find_field('Gender', type: :select)[:required]).to be == ''
      end
    end

    with ':required! and required: false' do
      view -> { Proscenium::UI::Form.new(user) } do |f|
        f.select_field :gender, :required!, required: false
      end

      it 'expects required to be false' do
        expect(view.find_field('Gender', type: :select)[:required]).to be_nil
      end
    end
  end

  with ':required! and no value' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :gender, :required!
    end

    it 'includes empty option' do
      expect(view.has_select?('Gender', options: ['', 'Male', 'Female', 'Other'])).to be_truthy
    end
  end

  with 'include_blank: false' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :gender, include_blank: false
    end

    it 'does not include empty option' do
      expect(view.has_select?('Gender', options: %w[Male Female Other])).to be_truthy
    end
  end

  with 'include_blank: String' do
    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :gender, include_blank: 'Select'
    end

    it 'includes empty option with text' do
      expect(view.has_select?('Gender', options: %w[Select Male Female Other])).to be_truthy
    end
  end

  with ':label' do
    view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
      f.select_field :gender, label: 'Foobar'
    end

    it 'overrides label' do
      expect(view.find('label').native.inner_html).to be =~ %r{^<div><span>Foobar</span></div>}
    end
  end

  with ':class' do
    view -> { Proscenium::UI::Form.new(user, url: '/') } do |f|
      f.select_field :gender, class: 'my_class'
    end

    it 'appends class value to field wrapper' do
      expect(view.find('pui-field')[:class]).to be == 'field-eacb39cc my_class'
    end
  end

  with ':typeahead!' do
    def before
      super
      Tag.create! [{ name: 'tag1' }, { name: 'tag2' }]
    end

    view -> { Proscenium::UI::Form.new(user) } do |f|
      f.select_field :tags, :typeahead!
    end

    it 'should render a component div' do
      expect(view.has_no_selector?('select')).to be_truthy
      expect(view.has_selector?('[data-proscenium-component-path]')).to be_truthy
    end

    # FIXME: react component manefr failing in trest env
    # describe 'javascript' do
    #   include Capybara::DSL

    #   it 'renders' do
    #     visit '/component_previews/_/hue/app/components/form/previews/select_typeahead'

    #     expect(page.has_button?('open menu', enable_aria_label: true)).to be_truthy
    #   end
    # end
  end
end
