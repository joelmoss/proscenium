# frozen_string_literal: true

module UI
  class BreadcrumbsController < UIController
    include Proscenium::UI::Breadcrumbs::Control
    add_breadcrumb 'Breadcrumbs'

    def index
      render Breadcrumbs::IndexView.new
    end
  end
end
