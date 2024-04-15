# frozen_string_literal: true

class UI::Form::TextFieldView < UILayout
  def view_template
    h1 { 'Form::TextField' }

    markdown %(
      Renders an `<input>` with a type of "text".
    )

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }
      markdown %(
        Render `Proscenium::UI::Form` with an ActiveRecord model instance and a block
        that defines the inputs you wish to use. Each input is called a form "field", and expects
        to be given the name of an attribute on the model as its first argument.
      )

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.text_field :name
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.text_field :name
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
        plain 'Arguments'
        ul do
          li do
            a(href: '#attribute') { code { 'attribute' } }
          end
          li do
            a(href: '#hint') { code { 'hint' } }
          end
          li do
            a(href: '#error') { code { 'error' } }
          end
        end
      end
    end
  end
end
