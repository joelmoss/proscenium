# frozen_string_literal: true

require 'open3'

module Proscenium
  class Middleware
    class Base
      include ActiveSupport::Benchmarkable

      # Error when the result of the build returns an error. For example, when esbuild returns
      # errors.
      class CompileError < StandardError; end

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

      def renderable?
        file_readable?
      end

      def file_readable?(file = @request.path_info)
        return unless (path = clean_path(file))

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
        @content_type ||
          ::Rack::Mime.mime_type(::File.extname(@request.path_info), nil) ||
          'application/javascript'
      end

      def render_response(content)
        response = Rack::Response.new
        response.write content
        response.content_type = content_type
        response['X-Proscenium-Middleware'] = name

        if Proscenium.config.cache_query_string
          response['Cache-Control'] = "public, max-age=#{2.days.to_i}"
        end

        yield response if block_given?

        response.finish
      end

      def build(cmd)
        stdout, stderr, status = Open3.capture3(cmd)

        unless status.success?
          raise self.class::CompileError, stderr if status.exitstatus == 2

          raise BuildError, stderr
        end

        unless stderr.empty?
          raise BuildError, "Proscenium build of #{name}:'#{@request.fullpath}' failed -- #{stderr}"
        end

        stdout
      end

      def benchmark(type)
        super logging_message(type)
      end

      # rubocop:disable Style/FormatStringToken
      def logging_message(type)
        format '[Proscenium] Request (%s) %s for %s at %s',
               type, @request.fullpath, @request.ip, Time.now.to_default_s
      end
      # rubocop:enable Style/FormatStringToken

      def logger
        Rails.logger
      end

      def name
        @name ||= self.class.name.split('::').last.downcase
      end
    end
  end
end
