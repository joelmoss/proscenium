# frozen_string_literal: true

class UI::Form::TelFieldView < UILayout
  def template
    h1 { 'Form::TelField' }

    markdown %(
      Renders an `<input>` with a type of "tel", along with country selection, and input masking
      based on the telephone format for the selected country.
    )

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.tel_field :phone
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.tel_field :phone
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
