# frozen_string_literal: true

class UI::UJS::DisableWithView < UILayout
  register_element :ujs_disable_with

  def template
    h1 do
      plain 'UJS '
      code { 'disable-with' }
    end
    p do
      plain 'Using the '
      code { 'data-disable-with' }
      plain %(
        data attribute, this prevents double form submission by disabling the submit button while
        the form is being submitted. The button text is replaced with a "Please wait..." message,
        and can be customised.
      )
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
          import startUJS from "@proscenium/ujs";
          startUJS();
        JS
      end

      p do
        %(
        Then simply use the `data-disable-with` attribute on any element to disable the submit
        button upon submit.
      )
      end

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { disable_with: true } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_disable_with do
          form do
            button(type: :submit, data: { disable_with: true }) { 'Click Me' }
          end
        end
      end
    end

    section do
      h2(id: 'customise-the-disabled-text') { 'Customise the Disabled Text' }
      p do
        %(
        By default, the button will display the text "Please wait..." when it is disabled. You can
        customise this by passing a string to the `data-disable-with` attribute.
      )
      end

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { disable_with: 'Loading forever...' } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_disable_with do
          form do
            button(type: :submit, data: { disable_with: 'Loading forever...' }) do
              'Click Me'
            end
          end
        end
      end

      p { 'And of course, you can pass false to disable the disabling completely.' }

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { disable_with: 'false' } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_disable_with do
          form do
            button(type: :submit, data: { disable_with: 'false' }) do
              'Click Me'
            end
          end
        end
      end
    end

    section do
      h2 id: 'combine-with-confirm' do
        plain 'Combine with '
        code { 'confirm' }
      end

      p do
        code { 'disable_with' }
        plain ' works perfectly with '
        a href: :ui_ujs_confirm do
          code { 'confirm' }
        end
        plain ':'
      end

      render CodeBlockComponent.new :html do
        button type: 'submit', data: { disable_with: true, confirm: true } do
          'Click Me'
        end
      end

      render CodeStageComponent do
        ujs_disable_with do
          form do
            button(type: :submit, data: { disable_with: true, confirm: true }) { 'Click Me' }
          end
        end
      end
    end

    section do
      h2(id: 'manually-reset') { 'Manually Reset' }
      p do
        plain 'Sometimes, you may want to manually reset the button to its original state. The '
        code { 'resetDisableWith' }
        %(
        function can be called on the element to reset the disabled state. Useful for when
        handling form submission with JavaScript, and the button should be re-enabled.
      )
      end

      render CodeBlockComponent.new :javascript do
        unsafe_raw <<~JS
          document.querySelector('#my-form').addEventListener('submit', (event) => {
            if (!validateForm()) {
              // Form validation failed, so re-enable and reset the button...
              event.submitter.resetDisableWith()

              // ...and prevent submission.
              event.preventDefault()
            }
          })
        JS
      end

      render CodeBlockComponent.new :html do
        form id: 'my-form' do
          input type: 'submit', value: 'Click me', data: { disable_with: 'Validating...' }
        end
      end

      render CodeStageComponent do
        ujs_disable_with do
          form id: 'my-form' do
            input type: 'submit', value: 'Click me', data: { disable_with: 'Validating...' }
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
        a(href: '#customise-the-disabled-text') { 'Customise the Disabled Text' }
      end
      li do
        a href: '#combine-with-confirm' do
          plain 'Combine with '
          code { 'confirm' }
        end
      end
      li do
        a(href: '#manually-reset') { 'Manually Reset' }
      end
    end
  end
end
