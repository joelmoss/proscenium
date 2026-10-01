# frozen_string_literal: true

module Proscenium
  class Middleware
    class Base
      include ActiveSupport::Benchmarkable

      def self.attempt(request)
        new(request).renderable!&.attempt
      end

      def initialize(request)
        @request = request
      end

      def renderable!
        # The single funnel every subclass reaches, so the guard sits here rather than in
        # `renderable?` - a subclass that overrides that (RubyGems does) cannot skip it.
        return unless normalised_path

        renderable? ? self : nil
      end

      private

      # The request path, decoded and with `.` and `..` segments resolved. Everything below is
      # derived from this one value; see `Middleware.normalise_path` for why that matters.
      def normalised_path
        return @normalised_path if defined?(@normalised_path)

        @normalised_path = Middleware.normalise_path(@request.path)
      end

      def real_path
        @real_path ||= normalised_path
      end

      # @return [String] the path to the file without the leading slash which will be built.
      def path_to_build
        @path_to_build ||= normalised_path[1..]
      end

      def sourcemap?
        normalised_path.ends_with?('.map')
      end

      def renderable?
        file_readable?
      end

      # Probes the path exactly as it will be built. `real_path` is already decoded and cleaned, so
      # decoding it again here - as this once did - probed a different file than the one built
      # whenever the request was double-encoded: `%252e%252e` was built as a literal `%2e%2e`
      # segment but probed as `..`.
      def file_readable?
        path = sourcemap? ? real_path[0...-4] : real_path
        file_stat = File.stat(root_for_readable.join(path.delete_prefix('/').b).to_s)
      rescue SystemCallError
        false
      else
        file_stat.file? && file_stat.readable?
      end

      def root_for_readable
        Rails.root
      end

      def content_type
        case ::File.extname(path_to_build)
        when '.js', '.mjs', '.ts', '.tsx', '.jsx' then 'application/javascript'
        when '.css' then 'text/css'
        when '.map' then 'application/json'
        else
          ::Rack::Mime.mime_type(::File.extname(path_to_build), nil) || 'application/javascript'
        end
      end

      def render_response(result)
        content = result[:response]

        response = Rack::Response.new
        response['X-Proscenium-Middleware'] = name
        response.set_header 'SourceMap', "#{@request.path_info}.map"
        response.content_type = content_type
        response.etag = result[:content_hash]

        if @request.fresh?(response)
          response.status = 304
          response.body = []
        else
          response.write content
        end

        response.finish
      end

      def name
        @name ||= self.class.name.split('::').last.downcase
      end
    end
  end
end
