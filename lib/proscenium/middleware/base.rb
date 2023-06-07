# frozen_string_literal: true

require 'oj'

module Proscenium
  class Middleware
    class Base
      include ActiveSupport::Benchmarkable

      # Error when the result of the build returns an error. For example, when esbuild returns
      # errors.
      class CompileError < StandardError
        attr_reader :detail, :file

        def initialize(args)
          @detail = args[:detail]
          @file = args[:file]
          super "Failed to build '#{args[:file]}' -- #{detail}"
        end
      end

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
        @request.path
      end

      # @return [String] the path to the file without the leading slash which will be built.
      def path_to_build
        @request.path[1..]
      end

      def sourcemap?
        @request.path.ends_with?('.map')
      end

      def renderable?
        file_readable?
      end

      def file_readable?
        return unless (path = clean_path(sourcemap? ? real_path[0...-4] : real_path))

        file_stat = File.stat(Pathname(root).join(path.delete_prefix('/').b).to_s)
      rescue SystemCallError
        false
      else
        file_stat.file? && file_stat.readable?
      end

      def clean_path(file)
        path = Rack::Utils.unescape_path file.chomp('/').delete_prefix('/')
        Rack::Utils.clean_path_info path if Rack::Utils.valid_path? path
      end

      def root
        @root ||= Rails.root.to_s
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

      def render_response(content)
        response = Rack::Response.new
        response.write content
        response.content_type = content_type
        response['X-Proscenium-Middleware'] = name
        response.set_header 'SourceMap', "#{@request.path_info}.map"

        if Proscenium.config.cache_query_string && Proscenium.config.cache_max_age
          response.cache! Proscenium.config.cache_max_age
        end

        yield response if block_given?

        response.finish
      end

      def name
        @name ||= self.class.name.split('::').last.downcase
      end
    end
  end
end
