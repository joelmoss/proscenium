# frozen_string_literal: true

module Proscenium
  class Middleware
    extend ActiveSupport::Autoload

    # Error when the build command fails.
    class BuildError < StandardError; end

    autoload :Base
    autoload :Esbuild
    autoload :Engines

    def initialize(app)
      @app = app

      chunks_path = Rails.public_path.join('assets').to_s
      headers = Rails.application.config.public_file_server.headers || {}
      @chunk_handler = ::ActionDispatch::FileHandler.new(chunks_path, headers:)
    end

    def call(env)
      request = Rack::Request.new(env)

      return @app.call(env) if !request.get? && !request.head?
      return @chunk_handler.attempt(request.env) if request.path.match?(%r{^/_asset_chunks/})

      attempt(request) || @app.call(env)
    end

    private

    def attempt(request)
      return unless (type = find_type(request))

      # file_handler.attempt(request.env) || type.attempt(request)

      type.attempt request
    end

    def find_type(request)
      return Esbuild if Pathname.new(request.path).fnmatch?(app_path_glob, File::FNM_EXTGLOB)

      pathname = Pathname.new(request.path)
      Engines if pathname.fnmatch?(ui_path_glob, File::FNM_EXTGLOB) ||
                 pathname.fnmatch?(engines_path_glob, File::FNM_EXTGLOB)
    end

    def app_path_glob
      "/{#{Proscenium::ALLOWED_DIRECTORIES}}/**.{#{file_extensions}}"
    end

    def engines_path_glob
      names = Proscenium.config.engines.keys
      "/{#{names.join(',')}}/{#{Proscenium::ALLOWED_DIRECTORIES}}/**.{#{file_extensions}}"
    end

    def ui_path_glob
      "/proscenium/**.{#{file_extensions}}"
    end

    def file_extensions
      @file_extensions ||= FILE_EXTENSIONS.join(',')
    end

    # TODO: handle precompiled assets
    # def file_handler
    #   ::ActionDispatch::FileHandler.new Rails.public_path.join('assets').to_s,
    #                                     headers: { 'X-Proscenium-Middleware' => 'precompiled' }
    # end
  end
end
