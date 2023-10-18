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
    #
    # rubocop:disable Metrics/*
    def self.resolve(path)
      self.resolved ||= {}

      self.resolved[path] ||= begin
        if path.start_with?('./', '../')
          raise ArgumentError, 'path must be an absolute file system or URL path'
        end

        if path.start_with?('@proscenium/')
          "/#{path}"
        elsif path.start_with?(Proscenium.ui_path.to_s)
          path.delete_prefix Proscenium.root.join('lib').to_s
        elsif (engine = Proscenium.config.engines.find { |e| path.start_with? "#{e.root}/" })
          path.sub(/^#{engine.root}/, "/#{engine.engine_name}")
        elsif path.start_with?("#{Rails.root}/")
          path.delete_prefix Rails.root.to_s
        else
          Builder.resolve path
        end
      end
    end
    # rubocop:enable Metrics/*
  end
end
