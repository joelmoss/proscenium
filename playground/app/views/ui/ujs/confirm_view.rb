# frozen_string_literal: true

class UI::UJS::ConfirmView < UILayout
  register_element :ujs_confirm

  def view_template
    h1 do
      plain 'UJS '
      code { 'confirm' }
    end
    p do
      plain 'Presents a confirmation dialog when a form is submitted by simply defining a '
      code { 'data-confirm' }
      plain %(
        attribute. This is useful for actions that
        change data, to prevent accidental submissions. It uses the browser's native
      )
      code { 'window.confirm()' }
      plain ' dialog to ask the user if they are sure they want to proceed.'
    end

    section do
      h2(id: 'basic-usage') { 'Basic Usage' }
      p do
        %(
          All the following examples require just this snippet of JavaScript to be included in your
          application:
        )
      end

      render CodeBlockComponent.new :javascript do
        unsafe_raw <<~JS
          import startUJS from "proscenium/ujs";
          startUJS();
        JS
      end

      p do
        %(
        Then simply use the `data-confirm` attribute on any element to trigger a confirmation dialog
        upon submit.
      )
      end

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { confirm: true } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_confirm do
          form do
            button(type: :submit, data: { confirm: true }) { 'Click Me' }
          end
        end
      end

      p do
        %(
        Note that this is intended only for buttons on form submission. It will not work with links.
        This is because it is recommended that buttons are used for actions that change data, while
        links are used for navigation.
      )
      end
    end

    section do
      h2(id: 'customise-the-dialog-text') { 'Customise the Dialog Text' }
      p do
        %(
        By default, the dialog will display the text "Are you sure?". You can customise this text by
        passing a string to the `data-confirm` attribute.
      )
      end

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { confirm: 'What? You really want to do this? 😱' } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_confirm do
          form do
            button(type: :submit, data: { confirm: 'What? You really want to do this? 😱' }) do
              'Click Me'
            end
          end
        end
      end

      p { 'And of course, you can pass false to disable the confirmation dialog entirely.' }

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { confirm: 'false' } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_confirm do
          form do
            button(type: :submit, data: { confirm: 'false' }) do
              'Click Me'
            end
          end
        end
      end
    end

    section do
      h2(id: 'combine-with-disable-with') do
        plain 'Combine with '
        code { 'disable-with' }
      end

      p do
        code { 'confirm' }
        plain ' works perfectly with '
        a href: :ui_ujs_disable_with do
          code { 'disable-with' }
        end
        plain ':'
      end

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { confirm: true, disable_with: true } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_confirm do
          form do
            button(type: :submit, data: { confirm: true, disable_with: true }) { 'Click Me' }
          end
        end
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
        a(href: '#customise-the-dialog-text') { 'Customise the Dialog Text' }
      end
      li do
        a href: '#combine-with-disable-with' do
          plain 'Combine with '
          code { 'disable-with' }
        end
      end
    end
  end
end
