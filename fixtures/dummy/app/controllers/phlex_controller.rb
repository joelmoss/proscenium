# frozen_string_literal: true

class PhlexController < ApplicationController
  layout false

  sideload_assets false

  def basic
    render Phlex::BasicView.new
  end

  def include_assets
    render Phlex::IncludeAssetsView.new
  end
end
