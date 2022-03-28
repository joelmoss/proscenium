# frozen_string_literal: true

module Proscenium
  module Middleware
    class Base
      include ActiveSupport::Benchmarkable

      def self.attempt(request)
        new(request).attempt
      end

      def initialize(request)
        @request = request
      end

      private

      def file_readable?(file = @request.path_info)
        return unless (path = clean_path(file))

        file_stat = File.stat(Rails.root.join(path.delete_prefix('/').b).to_s)
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
    end
  end
end
