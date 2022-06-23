# frozen_string_literal: true

module Proscenium
  module Middleware
    # Serves proscenium runtime code.
    class Runtime < Base
      def attempt
        benchmark :runtime do
          render_response build("#{proscenium_cli} #{root} #{@request.path} javascript")
        end
      end

      private

      def renderable?
        return unless @request.path_info.start_with?('/proscenium-runtime/')
        return unless /\.js(\.map)?$/i.match?(@request.path_info)

        @request.path_info = @request.path_info.sub(%r{^/proscenium-runtime/}, 'runtime/')

        if @request.path_info.ends_with?('.js.map')
          @content_type = 'application/json'
          file_readable? @request.path_info.sub(/\.map$/, '')
        else
          file_readable?
        end
      end

      def root
        @root ||= Pathname.new(__dir__).join('../')
      end
    end
  end
end
