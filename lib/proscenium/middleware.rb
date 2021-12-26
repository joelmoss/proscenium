# frozen_string_literal: true

require 'proscenium/builder'

module Proscenium
  class Middleware
    def initialize(app)
      @app = app
      @builder = Proscenium::Builder.new
    end

    def call(env)
      @builder.attempt(env) || @app.call(env)
    end
  end
end
