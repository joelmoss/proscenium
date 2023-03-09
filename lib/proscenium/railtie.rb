# frozen_string_literal: true

require 'rails'

ENV['RAILS_ENV'] = Rails.env

module Proscenium
  FILE_EXTENSIONS = ['js', 'mjs', 'jsx', 'css', 'js.map', 'mjs.map', 'jsx.map', 'css.map'].freeze

  # These globs should actually be Deno supported globs, and not ruby globs. This is because when
  # precompiling, the glob paths are passed as is to the compiler run by Deno.
  #
  # See https://doc.deno.land/https://deno.land/std@0.145.0/path/mod.ts/~/globToRegExp
  MIDDLEWARE_GLOB_TYPES = {
    application: "/**.{#{FILE_EXTENSIONS.join(',')}}",
    runtime: '/proscenium-runtime/**.{js,jsx,js.map,jsx.map}',
    npm: %r{^/npm:.+},
    gem: %r{^/gem:.+},
    url: %r{^/url:https?%3A%2F%2F}
  }.freeze

  APPLICATION_INCLUDE_PATHS = ['config', 'app/views', 'lib', 'node_modules'].freeze

  class << self
    def config
      @config ||= Railtie.config.proscenium
    end
  end

  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium

    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.side_load = true
    config.proscenium.cache_query_string = Rails.env.production? && ENV.fetch('REVISION', nil)
    config.proscenium.cache_max_age = 2_592_000 # 30 days
    config.proscenium.include_paths = Set.new(APPLICATION_INCLUDE_PATHS)
    config.proscenium.css_mixin_paths = Set[]

    # A hash of gems that can be side loaded. Assets from gems listed here can be side loaded.
    #
    # Example:
    #   config.proscenium.side_load_gems['proscenium-stage'] = {
    #     root: root,
    #     package_name: '@proscenium/stage'
    #   }
    config.proscenium.side_load_gems = {}

    config.before_configuration do |app|
      app.config.proscenium.css_mixin_paths = Set[app.root.join('lib')]
    end

    initializer 'proscenium.configuration' do |app|
      options = app.config.proscenium
      options.include_paths = Set.new(APPLICATION_INCLUDE_PATHS) if options.include_paths.blank?
    end

    initializer 'proscenium.side_load' do
      Proscenium::Current.loaded ||= SideLoad::EXTENSIONS.to_h { |e| [e, Set.new] }
    end

    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware
      app.middleware.insert_after ActionDispatch::Static, Rack::ETag, 'no-cache'
      app.middleware.insert_after ActionDispatch::Static, Rack::ConditionalGet
    end

    initializer 'proscenium.helpers' do |_app|
      ActiveSupport.on_load(:action_view) do
        ActionView::Base.include Proscenium::Helper

        if Rails.application.config.proscenium.side_load
          ActionView::TemplateRenderer.prepend SideLoad::Monkey::TemplateRenderer
          ActionView::PartialRenderer.prepend SideLoad::Monkey::PartialRenderer
        end

        ActionView::Helpers::UrlHelper.prepend Proscenium::LinkToHelper
      end
    end
  end
end
