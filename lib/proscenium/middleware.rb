# frozen_string_literal: true

module Proscenium
  class Middleware
    extend ActiveSupport::Autoload

    # Error when the build command fails.
    class BuildError < StandardError; end

    autoload :Base
    autoload :Esbuild
    autoload :Runtime
    autoload :OutsideRoot

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      return @app.call(env) if !request.get? && !request.head?

      attempt(request) || @app.call(env)
    end

    private

    # Look for the precompiled file in public/assets first, then fallback to the Proscenium
    # middleware that matches the type of file requested, ie: .js => esbuild.
    # See Rails.application.config.proscenium.glob_types.
    def attempt(request)
      return unless (type = find_type(request))

      file_handler.attempt(request.env) || type.attempt(request)
    end

    # Returns the type of file being requested using Rails.application.config.proscenium.glob_types.
    def find_type(request)
      path = Pathname.new(request.path)

      # Non-production only!
      if request.query_string == 'outsideRoot'
        return if Rails.env.production?
        return OutsideRoot if path.fnmatch?(glob_types[:outsideRoot], File::FNM_EXTGLOB)
      end

      return Runtime if path.fnmatch?(glob_types[:runtime], File::FNM_EXTGLOB)
      return Esbuild if path.fnmatch?(glob_types[:esbuild], File::FNM_EXTGLOB)
    end

    def file_handler
      ::ActionDispatch::FileHandler.new Rails.public_path.join('assets').to_s,
                                        headers: { 'X-Proscenium-Middleware' => 'precompiled' }
    end

    def glob_types
      Rails.application.config.proscenium.glob_types
    end
  end
end
