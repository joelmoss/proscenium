# frozen_string_literal: true

module Proscenium
  class Middleware
    extend ActiveSupport::Autoload

    class BuildError < Error; end

    autoload :Base
    autoload :Esbuild
    autoload :RubyGems
    autoload :SilenceRequest

    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      return @app.call(env) if !request.get? && !request.head?

      if request.path.match?(CHUNKS_PATH)
        ::ActionDispatch::FileHandler.new(
          Proscenium.config.output_path.to_s,
          headers: {
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

      if pathname.fnmatch?(GEMS_PATH_GLOB, File::FNM_EXTGLOB)
        RubyGems
      elsif pathname.fnmatch?(APP_PATH_GLOB, File::FNM_EXTGLOB)
        Esbuild
      end
    end
  end
end
