# frozen_string_literal: true

module Proscenium
  class Middleware
    class Esbuild < Base
      class CompileError < Base::CompileError
        def initialize(args)
          detail = args[:detail]
          detail = JSON.parse(detail, mode: :strict)

          args['detail'] = if detail['location']
                             "#{detail['text']} in #{detail['location']['file']}:" +
                               detail['location']['line'].to_s
                           else
                             detail['text']
                           end

          super
        end
      end

      def attempt
        render_response Builder.build_to_string(path_to_build, cache_query_string:)
      rescue Builder::CompileError => e
        raise self.class::CompileError, { file: @request.fullpath, detail: e.message }, caller
      end
    end
  end
end
