# frozen_string_literal: true

module Proscenium
  module Middleware
    # Serves CSS with parcel-css.
    class Stylesheet < Base
      def attempt
        return unless renderable?

        options = ['--nesting', '--custom-media', '--targets', "'>= 0.25%'"]
        options << '-m' if Rails.env.production?

        benchmark :stylesheet do
          render_response build("#{parcel_cli} #{options.join ' '} #{root}#{@request.path}")
        end
      end

      private

      def renderable?
        return unless /\.css(\.map)?$/i.match?(@request.path_info)

        if @request.path_info.end_with?('.css.map')
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
                          '/Users/joelmoss/dev/parcel-css/target/aarch64-apple-darwin/release/parcel_css'
                        else
                          Rails.root.join('bin/parcel_css')
                        end
      end
    end
  end
end
