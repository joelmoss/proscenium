# frozen_string_literal: true

module Proscenium
  module Middleware
    # Transform JS with esbuild.
    class Javascript < Base
      def attempt
        benchmark :javascript do
          render_response build("#{proscenium_cli} #{root} #{@request.path[1..]} javascript")
        end
      end

      private

      def renderable?
        return unless /\.js(\.map)?$/i.match?(@request.path_info)

        if @request.path_info.end_with?('.js.map')
          @content_type = 'application/json'

          file_readable? @request.path_info.sub(/\.map$/, '')
        else
          file_readable?
        end
      end
    end
  end
end
