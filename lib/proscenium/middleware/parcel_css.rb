# frozen_string_literal: true

require 'oj'

module Proscenium
  class Middleware
    class ParcelCss < Base
      def attempt
        benchmark :parcelcss do
          with_custom_media { |path| build path }
        end
      end

      private

      def with_custom_media
        yield "#{root}#{@request.path}" unless custom_media?

        Tempfile.create do |f|
          contents = Pathname.new("#{root}#{@request.path}").read
          f.write contents, "\n", custom_media_path.read
          f.rewind

          yield f.path
        end
      end

      def build(path)
        results = super("#{cli} #{cli_options.join ' '} #{path}")
        render_response css_module? ? Oj.load(results, mode: :strict)['code'] : results
      end

      def custom_media?
        @custom_media ||= custom_media_path.exist?
      end

      def custom_media_path
        @custom_media_path ||= Rails.root.join('lib', 'custom_media_queries.css')
      end

      def cli
        Gem.bin_path 'proscenium', 'parcel_css'
      end

      def cli_options
        options = ['--nesting', '--targets', "'>= 0.25%'"]
        options << '--custom-media' if custom_media?

        if css_module?
          hash = Digest::SHA1.hexdigest(@request.path)[..7]
          options += ['--css-modules', '--css-modules-pattern', "'[local]#{hash}'"]
        end

        Rails.env.production? ? options << '-m' : options
      end

      def css_module?
        @css_module ||= /\.module\.css$/i.match?(@request.path_info)
      end
    end
  end
end
