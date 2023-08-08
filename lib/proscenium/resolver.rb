# frozen_string_literal: true

require 'active_support/current_attributes'

module Proscenium
  class Resolver < ActiveSupport::CurrentAttributes
    # TODO: cache this across requests in production.
    attribute :resolved

    # Resolve the given `path` to a URL path.
    #
    # @param path [String] Can be URL path, file system path, or bare specifier (ie. NPM package).
    # @return [String] URL path.
    def self.resolve(path) # rubocop:disable Metrics/AbcSize
      self.resolved ||= {}

      self.resolved[path] ||= begin
        if path.starts_with?('./', '../')
          raise ArgumentError, 'path must be an absolute file system or URL path'
        end

        if (gem = Proscenium.config.side_load_gems.find { |_, x| path.starts_with? "#{x[:root]}/" })
          unless (package_name = gem[1][:package_name] || gem[0])
            # TODO: manually resolve the path without esbuild
            raise PathResolutionFailed, path
          end

          Builder.resolve "#{package_name}/#{path.delete_prefix("#{gem[1][:root]}/")}"
        elsif path.starts_with?("#{Rails.root}/")
          path.delete_prefix Rails.root.to_s
        else
          Builder.resolve path
        end
      end
    end
  end
end
