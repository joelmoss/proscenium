# frozen_string_literal: true

class UIController < ApplicationController
  layout -> { UILayout }

  def index
    render UI::IndexView.new
  end
end
