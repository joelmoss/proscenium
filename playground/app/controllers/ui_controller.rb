# frozen_string_literal: true

class UIController < ApplicationController
  include Proscenium::UI::Breadcrumbs::Control
  add_breadcrumb 'UI', :ui

  def index
    render UI::IndexView.new
  end
end
