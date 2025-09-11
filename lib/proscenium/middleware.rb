# frozen_string_literal: true

module Proscenium
  class Middleware
    extend ActiveSupport::Autoload

    # Error when the build command fails.
    class BuildError < StandardError; end

    autoload :Base
    autoload :Esbuild
    autoload :RubyGems

    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      return @app.call(env) if !request.get? && !request.head?

      # If this is a request for an asset chunk, we want to serve it with a very long
      # cache lifetime, since these are content-hashed and will never change.
      if request.path.match?(%r{^/_asset_chunks/})
        ::ActionDispatch::FileHandler.new(
          Rails.public_path.join('assets').to_s,
          headers: {
            'Cache-Control' => "public, max-age=#{100.years}, immutable",
            'etag' => request.path.match(/-\$([a-z0-9]+)\$/i)[1]
          }
        ).attempt(env) || @app.call(env)
      else
        attempt(request) || @app.call(env)
      end
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
