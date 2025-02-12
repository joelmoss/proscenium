# frozen_string_literal: true

class UI::Form::TelFieldView < UILayout
  def view_template
    h1 { 'Form::TelField' }

    markdown %(
      Renders an `<input>` with a `type` of "tel", along with country selection, and input masking
      based on the telephone format for the selected country. Phone numbers are expected to be in
      [E.164](https://en.wikipedia.org/wiki/E.164) format, eg. `+441234567890`.
    )

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.tel_field :phone, value: '+441234567890'
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.tel_field :phone, value: '+441234567890'
        end
      end
    end

    section do
      h2(id: 'default-country') { 'Default Country' }

      markdown %(
        The country code is determined by the value. If the value is not present, the country code
        defaults to "US". You can override the default country by providing a `Symbol` to the
        `default_country` keyword argument, which should be the 2 letter country code
        ([ISO 3166-1 Alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2)).
      )

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.tel_field :phone, default_country: :gb
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.tel_field :phone, default_country: :gb
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
