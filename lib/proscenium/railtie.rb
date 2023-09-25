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

    # Rails engines to expose and allow Proscenium to serve their assets.
    #
    # A Rails engine that has assets, can add Proscenium as a gem dependency, and then add itself
    # to this list. Proscenium will then serve the engine's assets at the URL path beginning with
    # the engine name.
    #
    # Example:
    #   class Gem1::Engine < ::Rails::Engine
    #     config.proscenium.engines << self
    #   end
    config.proscenium.engines = Set.new

    config.action_dispatch.rescue_templates = {
      'Proscenium::Builder::BuildError' => 'build_error'
    }

    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Middleware
      # app.middleware.insert_after ActionDispatch::Static, Rack::ETag, 'no-cache'
      # app.middleware.insert_after ActionDispatch::Static, Rack::ConditionalGet
    end

    initializer 'proscenium.monkey_patches' do
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

# Monkey path ActionDispatch::DebugView to use our custom error template on BuildError exceptions.
class ActionDispatch::DebugView
  def initialize(assigns)
    paths = [RESCUES_TEMPLATE_PATH,
             Proscenium::Railtie.root.join('lib', 'proscenium', 'templates').to_s]
    lookup_context = ActionView::LookupContext.new(paths)
    super(lookup_context, assigns, nil)
  end
end
