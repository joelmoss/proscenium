# frozen_string_literal: true

module Proscenium
  module Middleware
    # Transform JSX with esbuild.
    class Jsx < Base
      def attempt
        return unless renderable?

        benchmark :jsx do
          render_response build("#{proscenium_cli} #{root} #{@request.path[1..]} jsx")
        end
      end

      private

      def renderable?
        /\.jsx$/i.match?(@request.path_info) && file_readable?
      end
    end
  end
end
