module Proscenium
  module Helper
    def compute_asset_path(path, options = {})
      return "/#{path}" if %i[javascript stylesheet].include?(options[:type])

      super
    end
  end
end
