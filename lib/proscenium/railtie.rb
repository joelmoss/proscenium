# frozen_string_literal: true

require 'rails'
require 'proscenium/log_subscriber'

ENV['RAILS_ENV'] = Rails.env

module Proscenium
  class << self
    def config
      @config ||= Railtie.config.proscenium
    end
  end

  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium

    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.debug = false
    config.proscenium.side_load = true
    config.proscenium.code_splitting = true

    # TODO: implement!
    config.proscenium.cache_query_string = Rails.env.production? && ENV.fetch('REVISION', nil)
    config.proscenium.cache_max_age = 2_592_000 # 30 days

    # List of environment variable names that should be passed to the builder, which will then be
    # passed to esbuild's `Define` option. Being explicit about which environment variables are
    # defined means a faster build, as esbuild will have less to do.
    config.proscenium.env_vars = Set.new

    # A hash of gems that can be side loaded. Assets from gems listed here can be side loaded.
    #
    # Because side loading uses URL paths, any gem dependencies that side load assets will fail,
    # because the URL path will be relative to the application's root, and not the gem's root. By
    # specifying a list of gems that can be side loaded, Proscenium will be able to resolve the URL
    # path to the gem's root, and side load the asset.
    #
    # Side loading gems rely on NPM and a package.json file in the gem root. This ensures that any
    # dependencies are resolved correctly. This is required even if your gem has no package
    # dependencies.
    #
    # Example:
    #   config.proscenium.side_load_gems['mygem'] = {
    #     root: gem_root,
    #     package_name: 'mygem'
    #   }
    config.proscenium.side_load_gems = {}

    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Middleware
      app.middleware.insert_after ActionDispatch::Static, Rack::ETag, 'no-cache'
      app.middleware.insert_after ActionDispatch::Static, Rack::ConditionalGet
    end

    initializer 'proscenium.monkey_views' do
      ActiveSupport.on_load(:action_view) do
        ActionView::TemplateRenderer.prepend Monkey::TemplateRenderer
        ActionView::PartialRenderer.prepend Monkey::PartialRenderer
      end
    end

    initializer 'proscenium.helper' do
      ActiveSupport.on_load(:action_view) do
        ActionView::Base.include Helper
      end

      ActiveSupport.on_load(:action_controller) do
        ActionController::Base.include EnsureLoaded
      end
    end
  end
end
