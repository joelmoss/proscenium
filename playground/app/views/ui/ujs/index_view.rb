# frozen_string_literal: true

class UI::UJS::IndexView < UILayout
  def view_template
    h1 { 'UJS: Unobtrusive JavaScript' }
    p do
      %(
        Provides some basic dynamic functionality to your HTML to make your app more interactive
        without writing any JavaScript. All in a very unobtrusive way!
      )
    end

    p { 'Just add this snippet of JavaScript into your application:' }

    render CodeBlockComponent.new :javascript do
      unsafe_raw <<~JS
        import startUJS from "proscenium/ujs";
        startUJS();
      JS
    end

    p { 'You now have the following functionality available by modifying your HTML:' }

    ul do
      li do
        a(href: :ui_ujs_confirm) { code { 'confirm' } }
        span { ' - force confirmation dialogs on form and button submission.' }
      end
      li do
        a(href: :ui_ujs_disable_with) { code { 'disable-with' } }
        span do
          %(
            - have submit buttons become automatically disabled on form submit to prevent
            double-clicking.
          )
        end
      end
    end
  end
end
