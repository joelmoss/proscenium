# frozen_string_literal: true

class UI::IndexView < UILayout
  def view_template
    ul do
      li do
        a(href: ui_ujs_path) { 'UJS' }
      end
      li do
        a(href: ui_breadcrumbs_path) { 'Breadcrumbs' }
      end
      li do
        a(href: ui_form_path) { 'Form' }
      end
    end
  end
end
