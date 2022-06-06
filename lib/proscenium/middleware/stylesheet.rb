# frozen_string_literal: true

require 'oj'

module Proscenium
  module Middleware
    # Serves CSS with parcel-css.
    class Stylesheet < Base
      def attempt
        return unless renderable?

        benchmark :stylesheet do
          results = build("#{parcel_cli} #{cli_options.join ' '} #{root}#{@request.path}")
          render_response css_module? ? Oj.load(results, mode: :strict)['code'] : results
        end
      end

      private

      def renderable?
        return unless /(\.module)?\.css(\.map)?$/i.match?(@request.path_info)

        if /(\.module)?\.css\.map$/i.match?(@request.path_info)
          @content_type = 'application/json'

          return true if file_readable?(@request.path_info.sub(/\.map$/, ''))

          if file_readable?(@request.path_info.sub(/\.css\.map$/, '.css'))
            @request.path_info = @request.path_info.sub(/\.css\.map$/, '.css.map')
            true
          end
        else
          file_readable?
        end
      end

      def parcel_cli
        @parcel_cli ||= if ENV['PROSCENIUM_TEST']
                          Pathname.pwd.join('exe', 'parcel_css').to_s
                        else
                          Rails.root.join('bin/parcel_css')
                        end
      end

      def cli_options
        options = ['--nesting', '--custom-media', '--targets', "'>= 0.25%'"]

        if css_module?
          hash = Digest::MD5.file("#{root}#{@request.path}").hexdigest[..7]
          options += ['--css-modules', '--css-modules-pattern', "'[local]#{hash}'"]
        end

        Rails.env.production? ? options << '-m' : options
      end

      def css_module?
        @css_module ||= /\.module\.css(\.map)?$/i.match?(@request.path_info)
      end
    end
  end
end
