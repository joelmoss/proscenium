# frozen_string_literal: true

module Proscenium
  class Middleware
    # Error when the build command fails.
    class BuildError < StandardError; end

    def initialize(app)
      @app = app

      chunks_path = Rails.public_path.join('assets').to_s
      headers = Rails.application.config.public_file_server.headers || {}
      @chunk_handler = ::ActionDispatch::FileHandler.new(chunks_path, headers:)
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      return @app.call(env) if !request.get? && !request.head?

      if request.path.match?(%r{^/_asset_chunks/})
        response = Rack::Response[*@chunk_handler.attempt(request.env)]
        response.etag = request.path.match(/-\$([a-z0-9]+)\$/i)[1]

        if Proscenium.config.cache_query_string && Proscenium.config.cache_max_age
          response.cache! Proscenium.config.cache_max_age
        end

        if request.fresh?(response)
          response.status = 304
          response.body = []
        end

        return response.finish
      end

      attempt(request) || @app.call(env)
    end

    private

    def attempt(request)
      return unless (type = find_type(request))

      type.attempt request
    end

    def find_type(request)
      pathname = Pathname.new(request.path)

      if pathname.fnmatch?(gems_path_glob, File::FNM_EXTGLOB)
        RubyGems
      elsif pathname.fnmatch?(app_path_glob, File::FNM_EXTGLOB)
        Esbuild
      end
    end

    def app_path_glob
      "/{#{Proscenium::ALLOWED_DIRECTORIES}}/**.{#{file_extensions}}"
    end

    def gems_path_glob
      "/node_modules/@rubygems/**.{#{file_extensions}}"
    end

    def file_extensions
      @file_extensions ||= FILE_EXTENSIONS.join(',')
    end
  end
end
