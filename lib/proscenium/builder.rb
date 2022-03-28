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

      runtimebuild || jsxbuild || cssbuild || render
    end

    private

    def runtimebuild
      return unless runtime_buildable?

      runtime_root = Pathname.new(__dir__).join('runtime')
      filename = @request.fullpath.sub(%r{^/proscenium-runtime/}, '')

      benchmark :runtime do
        render_response build("#{proscenium_cli} #{runtime_root} #{filename}")
      end
    end

    def render
      return unless renderable?

      benchmark :static do
        Rack::File.new(root, {}).call(@request.env)
      end
    end

    # Build the requested file with esbuild.
    def jsbuild
      return unless js_buildable?

      benchmark :cli do
        render_response build("#{proscenium_cli} #{root} #{@request.fullpath[1..]}")
      end
    end

    def jsxbuild
      return unless jsx_buildable?

      benchmark :cli do
        render_response build("#{proscenium_cli} #{root} #{@request.fullpath[1..]}")
      end
    end

    # Build the requested file with parcel-css.
    def cssbuild
      return
      return unless css_buildable?

      cli = '/Users/joelmoss/dev/parcel-css/target/debug/parcel_css'
      options = '--css-modules --nesting'
      output_file = Rails.root.join('tmp', SecureRandom.uuid)

      benchmark do
        # out = build("#{cli} #{options} --output-file #{output_file}.css #{root}#{@request.fullpath}")
        out = build("#{cli} #{root}#{@request.fullpath}")

        render_response out
      end
    end

    def build(cmd)
      stdout, stderr, status = Open3.capture3(cmd)

      raise Error, stderr unless status.success?
      raise "Proscenium build of '#{@request.fullpath}' failed: #{stderr}" unless stderr.empty?

      stdout
    end

    def render_response(content)
      response = Rack::Response.new
      response.write content
      response.content_type = content_type
      response.finish
    end

    # Is the request for plain JS?
    def renderable?
      # /\.js$/i.match?(@request.path_info) && file_readable?
      /\.(js|css)$/i.match?(@request.path_info) && file_readable?
    end

    # Is the request for JSX/CSS/CSSM?
    def js_buildable?
      /\.jsx?$/i.match?(@request.path_info) && file_readable?
    end

    def jsx_buildable?
      /\.jsx$/i.match?(@request.path_info) && file_readable?
    end

    def runtime_buildable?
      @request.path_info.start_with?('/proscenium-runtime/')
    end

    def css_buildable?
      /\.css$/i.match?(@request.path_info) && file_readable?
    end

    def content_type
      ::Rack::Mime.mime_type(::File.extname(@request.path_info), nil) || 'application/javascript'
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

    def proscenium_cli
      @proscenium_cli ||= if ENV['PROSCENIUM_TEST']
                            'deno run -A lib/proscenium/cli.js'
                          else
                            Rails.root.join('bin/proscenium')
                          end
    end

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
  end
end
