# frozen_string_literal: true

require 'rails'
require 'action_cable/engine'
require 'listen'

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
    url: %r{^/url:https?%3A%2F%2F}
  }.freeze

  APPLICATION_INCLUDE_PATHS = ['config', 'app/views', 'lib', 'node_modules', 'ruby_gems'].freeze

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
    config.proscenium.auto_reload = Rails.env.development?
    config.proscenium.auto_reload_paths ||= %w[lib app config]
    config.proscenium.auto_reload_extensions ||= /\.(css|jsx?)$/
    config.proscenium.include_paths = Set.new(APPLICATION_INCLUDE_PATHS)
    config.proscenium.include_ruby_gems = {}

    initializer 'proscenium.configuration' do |app|
      options = app.config.proscenium

      options.include_paths = Set.new(APPLICATION_INCLUDE_PATHS) if options.include_paths.blank?
      options.auto_reload_paths.filter! { |path| Dir.exist? path }
      options.cable_mount_path ||= '/proscenium-cable'
      options.cable_logger ||= Rails.logger
    end

    initializer 'proscenium.side_load' do |_app|
      Proscenium::Current.loaded ||= SideLoad::EXTENSIONS.to_h { |e| [e, Set.new] }
    end

    initializer 'proscenium.middleware' do |app|
      if Rails.env.production?
        app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware
      else
        app.middleware.use Proscenium::Middleware
      end
    end

    initializer 'proscenium.helpers' do |_app|
      ActiveSupport.on_load(:action_view) do
        ActionView::Base.include Proscenium::Helper

        if Rails.application.config.proscenium.side_load
          ActionView::TemplateRenderer.prepend SideLoad::Monkey::TemplateRenderer
        end

        ActionView::Helpers::UrlHelper.prepend Proscenium::LinkToHelper
      end
    end

    config.after_initialize do
      next unless config.proscenium.auto_reload

      @listener = Listen.to(*config.proscenium.auto_reload_paths,
                            only: config.proscenium.auto_reload_extensions) do |mod, add, rem|
        Proscenium::Railtie.websocket&.broadcast('reload', {
                                                   modified: mod,
                                                   removed: rem,
                                                   added: add
                                                 })
      end

      @listener.start
    end

    at_exit do
      @listener&.stop
    end

    class << self
      def websocket
        return @websocket unless @websocket.nil?
        return unless config.proscenium.auto_reload

        cable = ActionCable::Server::Configuration.new
        cable.cable = { adapter: 'async' }.with_indifferent_access
        cable.mount_path = config.proscenium.cable_mount_path
        cable.connection_class = -> { Proscenium::Connection }
        cable.logger = config.proscenium.cable_logger

        @websocket ||= ActionCable::Server::Base.new(config: cable)
      end

      def websocket_mount_path
        "#{mounted_path}#{config.proscenium.cable_mount_path}" if websocket
      end

      def mounted_path
        Proscenium::Railtie.routes.find_script_name({})
      end
    end
  end
end
