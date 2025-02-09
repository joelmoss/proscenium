# frozen_string_literal: true

module Proscenium
  class Middleware
    # This middleware handles requests for assets in Rails engines. An engine that wants to expose
    # its assets via Proscenium to the application must add itself to the list of engines in the
    # Proscenium config options `Proscenium.config.engines`.
    #
    # For example, we have a gem that exposes a Rails engine.
    #
    #   module Gem1
    #     class Engine < ::Rails::Engine
    #       config.proscenium.engines['gem1'] = root
    #     end
    #   end
    #
    # When this gem is installed in any Rails application, its assets will be available at the URL
    # `/gem1/...`. For example, if the gem has a file `lib/styles.css`, it can be requested at
    # `/gem1/lib/styles.css`.
    #
    class Engines < Esbuild
      def real_path
        @real_path ||= Pathname.new(@request.path.delete_prefix("/#{engine_name}")).to_s
      end

      def root_for_readable
        engine.last
      end

      def engine
        @engine ||= Proscenium.config.engines.find do |k, _|
          @request.path.start_with?("/#{k}")
        end
      end

      def engine_name
        engine.first
      end
    end
  end
end
