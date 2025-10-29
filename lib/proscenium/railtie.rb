# frozen_string_literal: true

require 'rails'

ENV['RAILS_ENV'] = Rails.env

module Proscenium
  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium

    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.debug = false
    config.proscenium.logging = true
    config.proscenium.bundle = true
    config.proscenium.side_load = true
    config.proscenium.code_splitting = true
    config.proscenium.ensure_loaded = :raise
    config.proscenium.cache_query_string = Rails.env.production? && ENV.fetch('REVISION', nil)
    config.proscenium.cache_max_age = 2_592_000 # 30 days
    config.proscenium.aliases = {}
    config.proscenium.esbuild_aliases = {}
    config.proscenium.external = Set['*.rjs', '*.gif', '*.jpg', '*.png', '*.woff2', '*.woff']
    config.proscenium.precompile = Set.new
    config.proscenium.output_dir = '/assets'

    # List of environment variable names that should be passed to the builder, which will then be
    # passed to esbuild's `Define` option. Being explicit about which environment variables are
    # defined means a faster build, as esbuild will have less to do.
    config.proscenium.env_vars = Set.new

    config.action_dispatch.rescue_templates = {
      'Proscenium::Builder::BuildError' => 'build_error'
    }

    config.after_initialize do |app|
      config.proscenium.output_path ||=
        Pathname.new(File.join(app.config.paths['public'].first, app.config.proscenium.output_dir))
      config.proscenium.manifest_path = config.proscenium.output_path.join('.manifest.json')

      Proscenium::Manifest.load!

      if config.proscenium.logging
        require 'proscenium/log_subscriber'
        Proscenium::LogSubscriber.attach_to :proscenium
      end

      ActiveSupport.on_load(:action_view) do
        include Proscenium::Helper
      end
    end

    initializer 'proscenium.debugging' do
      tpl_path = root.join('lib', 'proscenium', 'templates').to_s
      ActionDispatch::DebugView::RESCUES_TEMPLATE_PATHS << tpl_path
    end

    initializer 'proscenium.middleware' do |app|
      unless config.proscenium.logging
        app.middleware.insert_before Rails::Rack::Logger, Proscenium::Middleware::SilenceRequest
      end
      app.middleware.insert_before ActionDispatch::ActionableExceptions, Proscenium::Middleware
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

    rake_tasks do
      load 'proscenium/railties/compile.rake'
    end
  end
end
