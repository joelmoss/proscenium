# frozen_string_literal: true

module Proscenium
  class Middleware
    class Esbuild < Base
      def attempt
        render_response Builder.build_to_string(path_to_build)
      end
    end
  end
end
