# frozen_string_literal: true

class UI::Form::CheckboxFieldView < UILayout
  def view_template
    h1 { 'Form::CheckboxField' }

    markdown 'Renders an `<input>` with a `type` of "checkbox".'

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.checkbox_field :enabled
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.checkbox_field :enabled
        end
      end
    end

    section do
      h2(id: 'checked') { code { 'checked' } }

      markdown 'Manually check/uncheck the checkbox by passing the `checked` argument.'

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.checkbox_field :enabled, checked: true
          end
        RUBY
      end

      render CodeStageComponent do
        render Proscenium::UI::Form.new User.new do |f|
          f.checkbox_field :enabled, checked: true
        end
      end
    end

    section do
      h2(id: 'checked_value') { code { 'checked_value' } }

      markdown %(
        By default, the checked value is `1`. This can be overridden by passing the `checked_value`
        argument.
      )

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.checkbox_field :enabled, checked_value: 'yes'
          end
        RUBY
      end

      render CodeBlockComponent.new :html do
        unsafe_raw <<~RUBY
          <input name="user[enabled]" type="checkbox" value="yes">
        RUBY
      end
    end

    section do
      h2(id: 'unchecked_value') { code { 'unchecked_value' } }

      markdown %(
        By default, the unchecked value is `0`. This can be overridden by passing the
        `unchecked_value` argument.
      )

      render CodeBlockComponent.new :ruby do
        unsafe_raw <<~RUBY
          render Proscenium::UI::Form.new @user do |f|
            f.checkbox_field :enabled, unchecked_value: 'no'
          end
        RUBY
      end

      render CodeBlockComponent.new :html do
        unsafe_raw <<~RUBY
          <input name="user[enabled]" type="hidden" value="no">
        RUBY
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
            a(href: '#checked') { code { 'checked' } }
          end
          li do
            a(href: '#checked_value') { code { 'checked_value' } }
          end
          li do
            a(href: '#unchecked_value') { code { 'unchecked_value' } }
          end
        end
      end
    end
  end
end
