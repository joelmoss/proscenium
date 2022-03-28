# frozen_string_literal: true

require 'rails'

module Proscenium
  class Railtie < ::Rails::Railtie
    config.proscenium = ActiveSupport::OrderedOptions.new

    initializer 'proscenium.configuration' do |app|
      options = app.config.proscenium

      options.middleware = [:static] if options.middleware.nil?
    end

    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware::Manager
    end

    rake_tasks do
      Dir[File.join(File.dirname(__FILE__), '../tasks/*.rake')].each { |f| load f }
    end

    config.after_initialize do
      ActiveSupport.on_load(:action_view) do
        include Proscenium::Helper
        ActionView::TemplateRenderer.prepend SideLoad::Monkey::TemplateRenderer
      end
    end
  end
end
