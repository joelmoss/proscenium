# frozen_string_literal: true

class UI::Form::IndexView < UILayout
  def template
    h1 { 'Form' }

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form::Component.new @user do |f|
            f.text_field :name
            f.textarea_field :address
            f.select_field :country, options: %w[USA Canada Mexico]
            f.checkbox_field :active?
            f.radio_group :gender, options: %i[male female]
            f.submit 'Create User'
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form::Component.new User.new do |f|
          f.text_field :name
          f.textarea_field :address
          f.select_field :country, options: %w[USA Canada Mexico]
          f.checkbox_field :active?
          f.radio_group :gender, options: %i[male female]
          f.submit 'Create User'
        end
      end
    end

    section do
      h2(id: 'hints') { 'Hints' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form::Component.new @user do |f|
            f.text_field :name, hint: 'Your full name'
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form::Component.new User.new do |f|
          f.text_field :name, hint: 'Your full name'
        end
      end
    end
  end
end
