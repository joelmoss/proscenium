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
    def self.resolve(path)
      self.resolved ||= {}

      self.resolved[path] ||= begin
        if path.start_with?('./', '../')
          raise ArgumentError, 'path must be an absolute file system or URL path'
        end

        if path.start_with?('proscenium/')
          "/#{path}"
        elsif (engine = Proscenium.config.engines.find { |_, v| path.start_with? "#{v}/" })
          path.sub(/^#{engine.last}/, "/#{engine.first}")
        elsif path.start_with?("#{Rails.root}/")
          path.delete_prefix Rails.root.to_s
        else
          Builder.resolve path
        end
      end
    end
  end
end
