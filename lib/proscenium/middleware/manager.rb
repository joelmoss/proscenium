# frozen_string_literal: true

module Proscenium
  module Middleware
    class Manager
      def initialize(app)
        @app = app
      end

      def call(env)
        middleware = nil
        request = Rack::Request.new(env)

        return @app.call(env) if !request.get? && !request.head?

        Rails.application.config.proscenium.middleware.each do |m|
          if m.is_a?(Symbol) || m.is_a?(String)
            m = "Proscenium::Middleware::#{m.to_s.classify}".constantize
          end

          break if (middleware = m.attempt(request))
        end

        middleware || @app.call(env)
      end
    end
  end
end
