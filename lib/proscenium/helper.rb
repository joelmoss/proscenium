# frozen_string_literal: true

module Proscenium
  module Helper
    def compute_asset_path(path, options = {})
      if %i[javascript stylesheet].include?(options[:type])
        result = "/#{path}"

        if (qs = Proscenium.config.cache_query_string)
          result << "?#{qs}"
        end

        return result
      end

      super
    end
  end
end
