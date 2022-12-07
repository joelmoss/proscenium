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

    def side_load_stylesheets
      return unless Proscenium::Current.loaded

      Proscenium::Current.loaded[:css].map do |digest, path|
        stylesheet_link_tag(path, id: "_#{digest}")
      end.join("\n").html_safe
    end

    def side_load_javascripts(**options)
      return unless Proscenium::Current.loaded

      Proscenium::Current.loaded[:js].map do |digest, path|
        javascript_include_tag(path, options.merge(id: "_#{digest}"))
      end.join("\n").html_safe
    end

    def proscenium_dev
      return unless Proscenium.config.auto_reload

      javascript_tag %(
        import autoReload from '/proscenium-runtime/auto_reload.js';
        autoReload('#{Proscenium::Railtie.websocket_mount_path}');
      ), type: 'module', defer: true
    end
  end
end
