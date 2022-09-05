# frozen_string_literal: true

require 'rails'
require 'action_cable/engine'
require 'listen'

ENV['RAILS_ENV'] = Rails.env

module Proscenium
  # These globs should actually be Deno supported globs, and not ruby globs. This is because when
  # precompiling, the glob paths are passed as is to the compiler run by Deno.
  #
  # See https://doc.deno.land/https://deno.land/std@0.145.0/path/mod.ts/~/globToRegExp
  DEFAULT_GLOB_TYPES = {
    esbuild: '/{config,app,lib,node_modules}/**.{js,jsx,css}',
    runtime: '/proscenium-runtime/**.{js,jsx}'
  }.freeze

  class << self
    def config
      @config ||= Railtie.config.proscenium
    end
  end

  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium

    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.side_load = true
    config.proscenium.auto_reload = Rails.env.development?
    config.proscenium.auto_reload_paths ||= %w[lib app config]
    config.proscenium.auto_reload_extensions ||= /\.(css|jsx?)$/

    initializer 'proscenium.configuration' do |app|
      options = app.config.proscenium

      options.glob_types = DEFAULT_GLOB_TYPES if options.glob_types.blank?
      options.auto_reload_paths.filter! { |path| Dir.exist? path }
      options.cable_mount_path ||= '/proscenium-cable'
      options.cable_logger ||= Rails.logger
    end

    initializer 'proscenium.side_load' do |_app|
      Proscenium::Current.loaded ||= SideLoad::EXTENSIONS.to_h { |e| [e, Set[]] }
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
