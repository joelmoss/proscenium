# frozen_string_literal: true

module Proscenium
  class Middleware
    extend ActiveSupport::Autoload

    # Error when the build command fails.
    class BuildError < StandardError; end

    autoload :Base
    autoload :Esbuild
    autoload :ParcelCss
    autoload :Runtime

    MIDDLEWARE_CLASSES = {
      esbuild: Esbuild,
      parcelcss: ParcelCss,
      runtime: Runtime
    }.freeze

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

      file_handler.attempt(request.env) || MIDDLEWARE_CLASSES[type].attempt(request)
    end

    # Returns the type of file being requested using Rails.application.config.proscenium.glob_types.
    def find_type(request)
      return :runtime if request.path_info.start_with?('/proscenium-runtime/')

      path = Rails.root.join(request.path[1..])

      type, = glob_types.find do |_, globs|
        # TODO: Look for the precompiled file in public/assets first
        #   globs.any? { |glob| Rails.public_path.join('assets').glob(glob).any?(path) }

        globs.any? { |glob| Rails.root.glob(glob).any?(path) }
      end

      type
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
