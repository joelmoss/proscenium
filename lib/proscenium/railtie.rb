# frozen_string_literal: true

require 'rails'
require 'action_cable/engine'
require 'listen'

ENV['RAILS_ENV'] = Rails.env

module Proscenium
  DEFAULT_MIDDLEWARE = %i[runtime static].freeze

  class << self
    def config
      @config ||= Railtie.config.proscenium
    end
  end

  class Railtie < ::Rails::Engine
    isolate_namespace Proscenium
    config.proscenium = ActiveSupport::OrderedOptions.new
    config.proscenium.listen_paths ||= %w[lib app/views app/components]

    initializer 'proscenium.configuration' do |app|
      options = app.config.proscenium

      options.middleware = DEFAULT_MIDDLEWARE if options.middleware.nil?

      options.auto_refresh = true if options.auto_refresh.nil?

      options.listen = Rails.env.development? if options.listen.nil?
      options.listen_paths = options.listen_paths.map(&:to_s)
      options.listen_paths.filter! { |path| Dir.exist? path }

      options.cable_mount_path ||= '/proscenium-cable'
      options.cable_logger ||= Rails.logger
    end

    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware::Manager
    end

    rake_tasks do
      Dir[File.join(File.dirname(__FILE__), '../tasks/*.rake')].each { |f| load f }
    end

    config.after_initialize do
      ActiveSupport.on_load(:action_view) do
        include Proscenium::AssetHelper
        ActionView::TemplateRenderer.prepend SideLoad::Monkey::TemplateRenderer
        ActionView::Helpers::UrlHelper.prepend Proscenium::LinkToHelper
      end

      if config.proscenium.listen
        @listener = Listen.to(*config.proscenium.listen_paths,
                              only: /\.(css|jsx?)$/) do |modified, added, removed|
          Proscenium::Railtie.websocket&.broadcast('reload', {
                                                     modified: modified,
                                                     removed: removed,
                                                     added: added
                                                   })
        end

        @listener.start
      end
    end

    at_exit do
      @listener&.stop
    end

    class << self
      def websocket
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
