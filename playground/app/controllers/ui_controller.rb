# frozen_string_literal: true

class UIController < ApplicationController
  include Proscenium::UI::Breadcrumbs::Control
  add_breadcrumb 'UI', :ui
end
