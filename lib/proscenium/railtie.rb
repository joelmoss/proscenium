# frozen_string_literal: true

require 'rails'
require 'proscenium/log_subscriber'

ENV['RAILS_ENV'] = Rails.env

module Proscenium
  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium

    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.debug = false
    config.proscenium.bundle = true
    config.proscenium.side_load = true
    config.proscenium.code_splitting = true

    config.proscenium.ensure_loaded = :raise

    config.proscenium.cache_query_string = Rails.env.production? && ENV.fetch('REVISION', nil)
    config.proscenium.cache_max_age = 2_592_000 # 30 days

    # List of environment variable names that should be passed to the builder, which will then be
    # passed to esbuild's `Define` option. Being explicit about which environment variables are
    # defined means a faster build, as esbuild will have less to do.
    config.proscenium.env_vars = Set.new

    config.action_dispatch.rescue_templates = {
      'Proscenium::Builder::BuildError' => 'build_error'
    }

    config.after_initialize do |_app|
      ActiveSupport.on_load(:action_view) do
        include Proscenium::Helper
      end
    end

    initializer 'proscenium.ui' do
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym 'UI'
      end
    end

    initializer 'proscenium.debugging' do
      if Rails.gem_version >= Gem::Version.new('7.1.0')
        tpl_path = root.join('lib', 'proscenium', 'templates').to_s
        ActionDispatch::DebugView::RESCUES_TEMPLATE_PATHS << tpl_path
      end
    end

    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware
    end

    initializer 'proscenium.sideloading' do
      ActiveSupport.on_load(:action_controller) do
        ActionController::Base.include EnsureLoaded
        ActionController::Base.include SideLoad::Controller
      end
    end

    initializer 'proscenium.monkey_patches' do
      ActiveSupport.on_load(:action_view) do
        ActionView::TemplateRenderer.prepend Monkey::TemplateRenderer
        ActionView::PartialRenderer.prepend Monkey::PartialRenderer
      end
    end

    initializer 'proscenium.public_path' do |app|
      if app.config.public_file_server.enabled
        headers = app.config.public_file_server.headers || {}
        index = app.config.public_file_server.index_name || 'index'

        app.middleware.insert_after(ActionDispatch::Static, ActionDispatch::Static,
                                    root.join('public').to_s, index:, headers:)
      end
    end
  end
end
