# frozen_string_literal: true

class UI::IndexView < UILayout
  def template
    ul do
      li do
        a(href: ui_ujs_path) { 'UJS' }
      end
      li do
        a(href: ui_breadcrumbs_path) { 'Breadcrumbs' }
      end
    end
  end
end
