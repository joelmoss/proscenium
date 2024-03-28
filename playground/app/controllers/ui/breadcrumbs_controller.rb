# frozen_string_literal: true

class UI::BreadcrumbsController < UIController
  include Proscenium::UI::Breadcrumbs::Control

  def index
    add_breadcrumb 'Proscenium UI', :ui
    add_breadcrumb 'Components', :ui
    add_breadcrumb 'Breadcrumbs'

    render UI::Breadcrumbs::IndexView.new
  end
end
