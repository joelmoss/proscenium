# frozen_string_literal: true

require 'rails/railtie'

module Proscenium
  class Railtie < ::Rails::Railtie
    initializer 'proscenium.middleware' do |app|
      app.middleware.insert_after ActionDispatch::Static, Proscenium::Middleware
    end
  end
end
