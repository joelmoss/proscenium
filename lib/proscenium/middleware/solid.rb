# frozen_string_literal: true

module Proscenium
  module Middleware
    class Solid < Base
      def attempt
        benchmark :solid do
          render_response build("#{solid_cli} #{root} #{@request.path[1..]} solid")
        end
      end

      private

      def renderable?
        return unless /\.jsx?(\.map)?$/i.match?(@request.path_info)

        if @request.path_info.end_with?('.js.map')
          @content_type = 'application/json'

          return true if file_readable?(@request.path_info.sub(/\.map$/, ''))

          if file_readable?(@request.path_info.sub(/\.js\.map$/, '.jsx'))
            @request.path_info = @request.path_info.sub(/\.js\.map$/, '.jsx.map')
            true
          end
        else
          file_readable?
        end
      end

      def solid_cli
        @solid_cli ||= if ENV['PROSCENIUM_TEST']
                         'deno run -q --import-map import_map.json -A lib/proscenium/cli/solid.js'
                       else
                         Rails.root.join('bin/solid')
                       end
      end
    end
  end
end
