# frozen_string_literal: true

class UI::Form::SelectFieldView < UILayout
  def view_template
    h1 { 'Form::SelectField' }

    markdown %(
      Renders an `<select>` input.
    )

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.select_field :gender
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.select_field :gender
        end
      end
    end

    section do
      h2(id: 'enums') { 'ActiveRecord::Enum' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          class User < ActiveRecord::Base
            enum gender: [:male, :female, :other]
          end
        RUBY
      end

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.select_field :gender
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.select_field :gender
        end
      end
    end

    section do
      h2(id: 'associations') { 'ActiveRecord Associations' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          class User < ActiveRecord::Base
            belongs_to :fruit
          end

          class Fruit < ApplicationRecord
            has_many :users

            # The return value of this method is used as the option label.
            def to_s = name
          end
        RUBY
      end

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.select_field :fruit
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.select_field :fruit, label: 'Favorite Fruit'
        end
      end
    end

    section do
      h2(id: 'autocomplete') { code { 'autocomplete' } }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.select_field :fruit, autocomplete: true
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.select_field :fruit, autocomplete: true
        end
      end
    end
  end

  private

  def page_nav
    div do
      a(href: :ui_form) { unsafe_raw '&laquo; Form' }
    end

    ul do
      li do
        a(href: '#basic-usage') { 'Basic Usage' }
      end
      li do
        a(href: '#enums') { 'ActiveRecord::Enum' }
      end
      li do
        a(href: '#associations') { 'ActiveRecord Associations' }
      end
      li do
        plain 'Arguments'
        ul do
          li do
            a(href: '#autocomplete') { code { 'autocomplete' } }
          end
        end
      end
    end
  end
end
