# frozen_string_literal: true

class UI::Form::IndexView < UILayout
  def template
    h1 { 'Form' }
    markdown %(
      A form component that is used to render a form and its inputs in a consistent, and
      unobtrusive way. It is designed to be used only with Rails and follows the Rails form
      conventions.
    )
    markdown %(
      As with all *Proscenium::UI* components, the form component ships with extremely simple
      barebones styling, and sensible defaults. It is expected that you will provide your own
      styling to make it look the way you like.
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
            f.textarea_field :address
            f.select_field :country, options: %w[USA Canada Mexico]
            f.checkbox_field :active?
            f.radio_group :gender
            f.submit
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.text_field :name
          br
          f.textarea_field :address
          br
          f.select_field :country, options: %w[USA Canada Mexico]
          br
          f.checkbox_field :active?
          br
          f.radio_group :gender
          br
          f.submit
        end
      end
    end

    section do
      h2(id: 'form') { 'Form' }
      markdown %(
        Everything starts with a Form 🙄 and the `Proscenium::UI::Form` class.
      )
    end

    section do
      h2(id: 'fields') { 'Fields' }
      markdown %(
        We provide a field for each type of input you might want to use in a form. These match up
        with the HTML form control elements, including, but not limited to all `input`, `textarea`,
        and `select` elements.
      )
      ul do
        li do
          a(href: :ui_form_text_field) { code { 'text_field' } }
        end
        li do
          a(href: :ui_form_file_field) { code { 'file_field' } }
        end
        li do
          a(href: :ui_form_url_field) { code { 'url_field' } }
        end
        li do
          a(href: :ui_form_email_field) { code { 'email_field' } }
        end
        li do
          a(href: :ui_form_number_field) { code { 'number_field' } }
        end
        li do
          a(href: :ui_form_time_field) { code { 'time_field' } }
        end
        li do
          a(href: :ui_form_date_field) { code { 'date_field' } }
        end
        li do
          a(href: :ui_form_datetime_local_field) { code { 'datetime_local_field' } }
        end
        li do
          a(href: :ui_form_week_field) { code { 'week_field' } }
        end
        li do
          a(href: :ui_form_month_field) { code { 'month_field' } }
        end
        li do
          a(href: :ui_form_color_field) { code { 'color_field' } }
        end
        li do
          a(href: :ui_form_search_field) { code { 'search_field' } }
        end
        li do
          a(href: :ui_form_password_field) { code { 'password_field' } }
        end
        li do
          a(href: :ui_form_range_field) { code { 'range_field' } }
        end
        li do
          a(href: :ui_form_tel_field) { code { 'tel_field' } }
        end
        li do
          a(href: :ui_form_checkbox_field) { code { 'checkbox_field' } }
        end
        li do
          a(href: :ui_form_select_field) { code { 'select_field' } }
        end
        li do
          a(href: :ui_form_radio_group) { code { 'radio_group' } }
        end
        li do
          a(href: :ui_form_radio_field) { code { 'radio_field' } }
        end
        li do
          a(href: :ui_form_textarea_field) { code { 'textarea_field' } }
        end
        li do
          a(href: :ui_form_rich_textarea_field) { code { 'rich_textarea_field' } }
        end
        li do
          a(href: :ui_form_hidden_field) { code { 'hidden_field' } }
        end
      end
    end

    section do
      h2(id: 'bang-attributes') { 'Bang Attributes' }
      markdown %(
        Some attributes only accept a boolean value, being only true or false (eg. `required`,
        `disabled`). To set these attributes, you would usually pass a keyword argument with the
        same name as the attribute, and a boolean value like this
      )

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.text_field :name, required: true
          end
        RUBY
      end

      markdown %(
        However, for these kinds of attributes, we provide an alternative way to set them, called a
        "bang attribute", which is a positional argument as a `Symbol` with the same name as the
        attribute, and ending with a bang (`!`).
      )

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.text_field :name, :required!
          end
        RUBY
      end

      p { 'Any attribute that only accepts a boolean value can be set this way.' }
    end

    section do
      h2(id: 'field-hints') { 'Field Hints' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.text_field :name, hint: 'Your full name'
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.text_field :name, hint: 'Your full name'
        end
      end
    end

    section do
      h2(id: 'field-errors') { 'Field Errors' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.text_field :name, error: 'Fail!!'
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.text_field :name, error: 'Fail!!'
        end
      end
    end

    section do
      h2(id: 'custom-fields') { 'Custom Fields' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          class MyEmailField < Proscenium::UI::Form::Fields::Base
            def template
              field do
                label do
                  div style: 'display: flex;' do
                    input(name: field_name, type: :email, **build_attributes)
                    div { '@proscenium.com' }
                  end
                end
                hint
              end
            end
          end
        RUBY
      end

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.use_field MyEmailField, :email
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.use_field MyEmailField, :email
        end
      end
    end
  end

  class MyEmailField < Proscenium::UI::Form::Fields::Base
    def template
      field do
        label do
          div style: 'display: flex;' do
            input(name: field_name, type: :email, **build_attributes)
            div { '@proscenium.com' }
          end
        end
        hint
      end
    end
  end

  private

  def page_nav
    ul do
      li do
        a(href: '#basic-usage') { 'Basic Usage' }
      end
      li do
        a(href: '#form') { 'Form' }
      end
      li do
        a(href: '#fields') { 'Fields' }
        ul do
          li do
            a(href: :ui_form_text_field) { code { 'text_field' } }
          end
          li do
            a(href: :ui_form_file_field) { code { 'file_field' } }
          end
          li do
            a(href: :ui_form_url_field) { code { 'url_field' } }
          end
          li do
            a(href: :ui_form_email_field) { code { 'email_field' } }
          end
          li do
            a(href: :ui_form_number_field) { code { 'number_field' } }
          end
          li do
            a(href: :ui_form_time_field) { code { 'time_field' } }
          end
          li do
            a(href: :ui_form_date_field) { code { 'date_field' } }
          end
          li do
            a(href: :ui_form_datetime_local_field) { code { 'datetime_local_field' } }
          end
          li do
            a(href: :ui_form_week_field) { code { 'week_field' } }
          end
          li do
            a(href: :ui_form_month_field) { code { 'month_field' } }
          end
          li do
            a(href: :ui_form_color_field) { code { 'color_field' } }
          end
          li do
            a(href: :ui_form_search_field) { code { 'search_field' } }
          end
          li do
            a(href: :ui_form_password_field) { code { 'password_field' } }
          end
          li do
            a(href: :ui_form_range_field) { code { 'range_field' } }
          end
          li do
            a(href: :ui_form_tel_field) { code { 'tel_field' } }
          end
          li do
            a(href: :ui_form_checkbox_field) { code { 'checkbox_field' } }
          end
          li do
            a(href: :ui_form_select_field) { code { 'select_field' } }
          end
          li do
            a(href: :ui_form_radio_group) { code { 'radio_group' } }
          end
          li do
            a(href: :ui_form_radio_field) { code { 'radio_field' } }
          end
          li do
            a(href: :ui_form_textarea_field) { code { 'textarea_field' } }
          end
          li do
            a(href: :ui_form_rich_textarea_field) { code { 'rich_textarea_field' } }
          end
          li do
            a(href: :ui_form_hidden_field) { code { 'hidden_field' } }
          end
        end
      end
      li do
        a(href: '#bang-attributes') { 'Bang Attributes' }
      end
      li do
        a(href: '#field-hints') { 'Field Hints' }
      end
      li do
        a(href: '#field-errors') { 'Field Errors' }
      end
      li do
        a(href: '#custom-fields') { 'Custom Fields' }
      end
    end
  end
end
