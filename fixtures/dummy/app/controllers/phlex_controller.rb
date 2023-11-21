# frozen_string_literal: true

class PhlexController < ApplicationController
  layout false

  sideload_assets false

  def basic
    render Views::Phlex::Basic.new
  end

  def include_assets
    render Views::Phlex::IncludeAssets.new
  end
end
