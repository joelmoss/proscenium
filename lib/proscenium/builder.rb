# frozen_string_literal: true

require 'open3'
require 'active_support/benchmarkable'

module Proscenium
  # This endpoint serves JS and CSS files from anywhere within the rails root, via ESBuild. If no
  # file is found, it hands off to the main app.
  #
  # Only GET and HEAD requests are served. POST and other HTTP methods are handed off to the main
  # app.
  #
  # Only files in the root directory are served; path traversal is denied.
  class Builder
    include ActiveSupport::Benchmarkable

    class Error < StandardError; end

    def attempt(env)
      @request = Rack::Request.new(env)

      buildable? && build
    end

    private

    def build
      benchmark do
        stdout, stderr, status = run

        if status.success?
          raise "Proscenium build failed: #{stderr}" unless stderr.empty?
        else
          raise Error, stderr
        end

        response = Rack::Response.new(stdout)
        response.content_type = content_type
        response.finish
      end
    end

    def buildable?
      return if !@request.get? && !@request.head?
      return unless /\.(js(x)?|css)$/i.match?(@request.path_info)
      return unless file_readable?

      true
    end

    def run
      cmd = if %w[development test].include?(ENV['PROSCENIUM_ENV']&.to_s)
              'deno run -A lib/proscenium/cli.js'
            else
              Rails.root.join('bin/proscenium')
            end

      Open3.capture3 "#{cmd} #{root} #{@request.fullpath[1..]}" # , chdir: root
    end

    def content_type
      ::Rack::Mime.mime_type(::File.extname(@request.path_info), nil) || 'application/javascript'
    end

    def benchmark
      super logging_message
    end

    # rubocop:disable Style/FormatStringToken
    def logging_message
      format '%s Proscenium %s for %s', Time.now.to_default_s, @request.fullpath, @request.ip
    end
    # rubocop:enable Style/FormatStringToken

    def logger
      Rails.logger
    end

    def clean_path
      path = Rack::Utils.unescape_path @request.path_info.chomp('/').delete_prefix('/')
      Rack::Utils.clean_path_info path if Rack::Utils.valid_path? path
    end

    def file_readable?
      return unless (path = clean_path)

      file_stat = File.stat(Rails.root.join(path.delete_prefix('/').b).to_s)
    rescue SystemCallError
      false
    else
      file_stat.file? && file_stat.readable?
    end

    def root
      @root ||= Rails.root.to_s
    end
  end
end
