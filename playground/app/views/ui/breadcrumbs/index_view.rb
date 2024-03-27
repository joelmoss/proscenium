# frozen_string_literal: true

class UI::Breadcrumbs::IndexView < UILayout
  def template
    main do
      render Proscenium::UI::Breadcrumbs::Component.new home_path: :ui
    end
  end
end
