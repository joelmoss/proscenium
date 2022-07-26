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
    esbuild: [
      'lib/**/*.{js,jsx}',
      'app/components/**/*.{js,jsx}',
      'app/views/**/*.{js,jsx}'
    ],
    parcelcss: [
      'lib/**/*.css',
      'app/components/**/*.css',
      'app/views/**/*.css'
    ]
  }.freeze

  class << self
    def config
      @config ||= Railtie.config.proscenium
    end
  end

  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium

    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.listen_paths ||= %w[lib app]
    config.proscenium.listen_extensions ||= /\.(css|jsx?)$/
    config.proscenium.side_load = true

    initializer 'proscenium.configuration' do |app|
      options = app.config.proscenium

      options.glob_types = DEFAULT_GLOB_TYPES if options.glob_types.blank?

      options.auto_refresh = true if options.auto_refresh.nil?
      options.listen = Rails.env.development? if options.listen.nil?
      options.listen_paths.filter! { |path| Dir.exist? path }
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
      next unless config.proscenium.listen

      @listener = Listen.to(*config.proscenium.listen_paths,
                            only: config.proscenium.listen_extensions) do |mod, add, rem|
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
        return unless config.proscenium.auto_refresh

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
