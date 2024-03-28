# frozen_string_literal: true

class UIController < ApplicationController
  def index
    render UI::IndexView.new
  end
end
