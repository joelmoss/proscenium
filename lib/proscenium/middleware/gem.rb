# frozen_string_literal: true

module Proscenium
  class Middleware
    # Handles requests prefixed with "gem:", and returns the matching path from the locally
    # installed Ruby gem of the same name.
    #
    # For example, the URL `/proscenium/gem:my_gem/lib/stuff.css` will serve the file at
    # `[GEMS_PATH]/my_gem/lib/stuff.css`.
    class Gem < Esbuild
      private

      def real_path
        @real_path ||= super.delete_prefix "/gem:#{gem_name}"
      end

      # @override [Esbuild] Support paths prefixed with '/gem:[gem_name]' by rewriting the root to
      # be the the path of the gem identified by `gem_name` in the URL.
      def renderable?
        gem_spec && super
      end

      def gem_name
        @gem_name ||= @request.path.delete_prefix('/gem:').split(File::SEPARATOR).first
      end

      def gem_spec
        @gem_spec ||= Bundler.rubygems.loaded_specs(gem_name)
      end

      def root
        @root ||= Pathname.new(gem_spec.full_gem_path)
      end
    end
  end
end
