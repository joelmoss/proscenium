# frozen_string_literal: true

module Proscenium
  module Helper
    def compute_asset_path(path, options = {})
      return "/#{path}" if %i[javascript stylesheet].include?(options[:type])

      super
    end

    def side_load_stylesheets
      return unless Proscenium::Current.loaded

      stylesheet_link_tag(*Proscenium::Current.loaded[:css])
    end

    def side_load_javascripts(**options)
      return unless Proscenium::Current.loaded

      javascript_include_tag(*Proscenium::Current.loaded[:js], options)
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
