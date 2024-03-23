# frozen_string_literal: true

class UI::IndexView < UILayout
  def template
    h1 { 'Proscenium UI' }
    ul do
      li do
        a href: ui_breadcrumbs_path do
          'Breadcrumbs'
        end
      end
    end
  end
end
