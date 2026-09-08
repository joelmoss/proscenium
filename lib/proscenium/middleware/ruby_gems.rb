# frozen_string_literal: true

module Proscenium
  class Middleware
    class RubyGems < Esbuild
      def real_path
        @real_path ||= Pathname.new(gem_request_path.delete_prefix("#{gem_name}/")).to_s
      end

      # An unknown gem is "not mine", the same answer a missing file under an app path gets from
      # `Base#file_readable?`. Without this, `pathname_for!` raised out of the readability probe
      # and a request for a gem that is not in the Gemfile 500'd, while the sibling app-path
      # branch quietly passed the same shape of miss down the stack.
      def renderable?
        BundledGems.pathname_for(gem_name) && super
      end

      def root_for_readable
        BundledGems.pathname_for!(gem_name)
      end

      def gem_name
        @gem_name ||= gem_request_path.split('/').first
      end

      # Taken from the normalised path, so the gem name and the suffix describe the file that
      # will actually be built. Read from the request verbatim, `@rubygems/gem1/../index.js`
      # named gem1 and a suffix the readability probe then cleaned to `index.js` - approving
      # `<gem1>/index.js` while the builder resolved `../index.js` and served the file BESIDE
      # the gem root. Normalised, it names a gem called `index.js`, which is not bundled, so
      # the request passes through.
      def gem_request_path
        @gem_request_path ||= normalised_path.delete_prefix('/node_modules/@rubygems/')
      end
    end
  end
end
