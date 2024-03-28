# frozen_string_literal: true

class PagesController < ApplicationController
  def index
    render Pages::IndexView
  end
end
