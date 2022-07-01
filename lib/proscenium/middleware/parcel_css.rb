# frozen_string_literal: true

require 'oj'

module Proscenium
  class Middleware
    class ParcelCss < Base
      def attempt
        benchmark :parcelcss do
          results = build("#{cli} #{cli_options.join ' '} #{root}#{@request.path}")
          render_response css_module? ? Oj.load(results, mode: :strict)['code'] : results
        end
      end

      private

      def cli
        Gem.bin_path 'proscenium', 'parcel_css'
      end

      def cli_options
        options = ['--nesting', '--custom-media', '--targets', "'>= 0.25%'"]

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
