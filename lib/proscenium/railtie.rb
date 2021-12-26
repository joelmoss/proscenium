# frozen_string_literal: true

require 'rails'

module Proscenium
  class Railtie < ::Rails::Railtie
    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware
    end

    # config.after_initialize do
    #   ActiveSupport.on_load(:action_view) do
    #     include Proscenium::Helper
    #   end
    # end
  end
end
