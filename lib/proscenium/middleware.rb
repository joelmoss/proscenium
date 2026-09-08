# frozen_string_literal: true

module Proscenium
  class Middleware
    extend ActiveSupport::Autoload

    class BuildError < Error; end

    autoload :Base
    autoload :Esbuild
    autoload :RubyGems
    autoload :Vendor
    autoload :Chunks
    autoload :SilenceRequest

    # The given request path, percent-decoded and with `.` and `..` segments resolved. Nil for a
    # path Rack rejects outright, such as one containing a null byte.
    #
    # Every decision and every derived path in this subsystem is taken from this one form. The
    # alternative was three derivations from the raw path that disagreed: `find_type` matched the
    # allowed-directory glob against the request verbatim, `Base#file_readable?` normalised before
    # probing the disk, and `Base#path_to_build` kept the request verbatim again - so a request
    # could be routed by a directory it does not resolve to, approved against one file, and built
    # as a third.
    def self.normalise_path(path)
      unescaped = Rack::Utils.unescape_path(path.chomp('/').delete_prefix('/'))
      return unless Rack::Utils.valid_path?(unescaped)

      "/#{Rack::Utils.clean_path_info(unescaped)}"
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      request = ActionDispatch::Request.new(env)

      return @app.call(env) if !request.get? && !request.head?

      attempt(request) || @app.call(env)
    end

    private

    def attempt(request)
      return unless (type = find_type(request))

      type.attempt(request)
    end

    def find_type(request)
      # Matched against the normalised path, not the request, or the allowed-directory list is
      # bypassable: `/lib/../public/x.js` matches `APP_PATH_GLOB` as written and resolves to
      # `public/`, which is not an allowed directory - and it was built and served from there.
      return unless (path = Middleware.normalise_path(request.path))

      pathname = Pathname.new(path)

      if pathname.fnmatch?(GEMS_PATH_GLOB, File::FNM_EXTGLOB)
        RubyGems
      elsif pathname.fnmatch?(APP_PATH_GLOB, File::FNM_EXTGLOB)
        Esbuild
      end
    end
  end
end
