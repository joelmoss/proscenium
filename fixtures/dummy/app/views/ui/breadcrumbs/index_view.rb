# frozen_string_literal: true

class UI::Breadcrumbs::IndexView < ApplicationView
  def template
    h1 { 'Proscenium UI' }
    h2 { 'Breadcrumbs' }
    main do
      render Proscenium::UI::Breadcrumbs::Component.new home_path: :ui
    end
  end
end
