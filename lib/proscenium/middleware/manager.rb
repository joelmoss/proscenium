# frozen_string_literal: true

module Proscenium
  module Middleware
    class Manager
      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)

        return @app.call(env) if !request.get? && !request.head?

        middleware(request) || @app.call(env)
      end

      private

      def middleware(request)
        matched = nil

        Rails.application.config.proscenium.middleware.each do |m|
          m = middleware_class(m) if m.is_a?(Symbol) || m.is_a?(String)

          break if (matched = m&.attempt(request))
        end

        matched
      end

      def middleware_class(name)
        "Proscenium::Middleware::#{name.to_s.classify}".safe_constantize
      end
    end
  end
end
