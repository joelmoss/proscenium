# frozen_string_literal: true

module Proscenium
  module AssetHelper
    def compute_asset_path(path, options = {})
      return "/#{path}" if %i[javascript stylesheet].include?(options[:type])

      super
    end
  end
end
