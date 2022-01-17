# frozen_string_literal: true

require 'proscenium/builder'

module Proscenium
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      Proscenium::Builder.new.attempt(env) || @app.call(env)
    end
  end
end
