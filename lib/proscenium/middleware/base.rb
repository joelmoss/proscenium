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
        renderable? ? self : nil
      end

      private

      def real_path
        @real_path ||= @request.path
      end

      # @return [String] the path to the file without the leading slash which will be built.
      def path_to_build
        @path_to_build ||= @request.path[1..]
      end

      def sourcemap?
        @request.path.ends_with?('.map')
      end

      def renderable?
        file_readable?
      end

      def file_readable?
        return false unless (path = clean_path(sourcemap? ? real_path[0...-4] : real_path))

        file_stat = File.stat(root_for_readable.join(path.delete_prefix('/').b).to_s)
      rescue SystemCallError
        false
      else
        file_stat.file? && file_stat.readable?
      end

      def root_for_readable
        Rails.root
      end

      def clean_path(file)
        path = Rack::Utils.unescape_path file.chomp('/').delete_prefix('/')
        Rack::Utils.clean_path_info path if Rack::Utils.valid_path? path
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
