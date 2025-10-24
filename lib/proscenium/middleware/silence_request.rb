# frozen_string_literal: true

require 'active_support/logger_silence'

module Proscenium
  class Middleware::SilenceRequest
    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      if (request.get? || request.head?) && proscenium_request?(request)
        Rails.logger.silence { @app.call(env) }
      else
        @app.call(env)
      end
    end

    private

    def proscenium_request?(request)
      return true if request.path.match?(CHUNKS_PATH)

      pathname = Pathname.new(request.path)
      pathname.fnmatch?(GEMS_PATH_GLOB, File::FNM_EXTGLOB) ||
        pathname.fnmatch?(APP_PATH_GLOB, File::FNM_EXTGLOB)
    end
  end
end
