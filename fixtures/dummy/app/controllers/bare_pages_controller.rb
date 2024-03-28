# frozen_string_literal: true

class BarePagesController < ApplicationController
  layout 'bare'

  before_action :normalize_sideload_assets_params

  private

  def normalize_sideload_assets_params # rubocop:disable Metrics/AbcSize
    %i[sideload_view_assets sideload_layout_assets
       sideload_partial_assets sideload_partial_layout_assets].each do |key|
      next unless params[key]

      if params[key] == 'false'
        params[key] = false
      elsif params[key] == 'true'
        params[key] = true
      elsif params[key][:css] == 'false'
        params[key][:css] = false
      elsif params[key][:css] == 'true'
        params[key][:css] = true
      elsif params[key][:js] == 'false'
        params[key][:js] = false
      elsif params[key][:js] == 'true'
        params[key][:js] = true
      end
    end
  end
end
