# frozen_string_literal: true

module Proscenium
  class Middleware
    class RubyGems < Esbuild
      def real_path
        @real_path ||= Pathname.new(gem_request_path.delete_prefix("#{gem_name}/")).to_s
      end

      def root_for_readable
        BundledGems.pathname_for!(gem_name)
      end

      def gem_name
        @gem_name ||= gem_request_path.split('/').first
      end

      def gem_request_path
        @gem_request_path ||= @request.path.delete_prefix('/node_modules/@rubygems/')
      end
    end
  end
end
