# frozen_string_literal: true

class UIController < ApplicationController
  layout false

  def index
    render UI::IndexView.new
  end
end
