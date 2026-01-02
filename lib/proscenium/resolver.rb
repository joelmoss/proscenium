# frozen_string_literal: true

module Proscenium
  class Resolver
    mattr_accessor :resolved, instance_accessor: false, default: {}

    # Resolve the given `path` to a fully qualified URL path.
    #
    # @param path [String] URL path, file system path, or bare specifier (ie. NPM package).
    # @param as_array [Boolean] whether or not to return the manifest path, non-manifest path, and
    #   absolute file system path as an array. Only returns the resolved path if false (default).
    # @return [String, Array<String>]
    def self.resolve(path, as_array: false)
      if path.start_with?('./', '../')
        raise ArgumentError, '`path` must be an absolute file system or URL path'
      end

      resolved[path] ||= if (gem = BundledGems.paths.find { |_, v| path.start_with? "#{v}/" })
                           vpath = path.sub(/^#{gem.last}/, "@rubygems/#{gem.first}")
                           [Proscenium::Manifest[vpath], "/node_modules/#{vpath}", path]
                         elsif path.start_with?("#{Rails.root}/")
                           vpath = path.delete_prefix(Rails.root.to_s)
                           [Proscenium::Manifest[vpath], vpath, path]
                         else
                           [Proscenium::Manifest[path], *Builder.resolve(path)]
                         end

      as_array ? resolved[path] : resolved[path][0] || resolved[path][1]
    end

    def self.reset
      self.resolved = {}
    end
  end
end
