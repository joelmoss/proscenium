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

      return if !@request.get? && !@request.head?

      jsbuild || cssbuild || render
    end

    private

    def render
      return unless renderable?

      benchmark do
        Rack::File.new(root, {}).call(@request.env)
      end
    end

    # Build the requested file with esbuild.
    def jsbuild
      return unless js_buildable?

      cmd = if ENV['PROSCENIUM_TEST']
              'deno run -A lib/proscenium/cli.js'
            else
              Rails.root.join('bin/proscenium')
            end

      build do
        "#{cmd} #{root} #{@request.fullpath[1..]}"
      end
    end

    # Build the requested file with parcel-css.
    def cssbuild
      return unless css_buildable?

      build do
        "parcel_css minify #{root}#{@request.fullpath}"
      end
    end

    def build
      cmd = yield

      benchmark do
        stdout, stderr, status = Open3.capture3(cmd)

        if status.success?
          raise "Proscenium build ('#{cmd}') failed: #{stderr}" unless stderr.empty?
        else
          raise Error, stderr
        end

        response = Rack::Response.new
        response.write stdout
        response.content_type = content_type
        response.finish
      end
    end

    # Is the request for plain JS?
    def renderable?
      # /\.js$/i.match?(@request.path_info) && file_readable?
      false
    end

    # Is the request for JSX/CSS/CSSM?
    def js_buildable?
      /\.jsx?$/i.match?(@request.path_info) && file_readable?
    end

    def css_buildable?
      /\.css$/i.match?(@request.path_info) && file_readable?
    end

    def content_type
      ::Rack::Mime.mime_type(::File.extname(@request.path_info), nil) || 'application/javascript'
    end

    def benchmark
      super logging_message
    end

    # rubocop:disable Style/FormatStringToken
    def logging_message
      format 'Proscenium %s for %s at %s', @request.fullpath, @request.ip, Time.now.to_default_s
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
