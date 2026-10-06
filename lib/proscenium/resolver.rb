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
      # Normalised before anything reads it, the guard and the cache key included. The bun test
      # harness hands this Bun's own spelling of a module path, which on Windows is `D:\...`;
      # matched against a slash-form Rails.root it fell through to the Go resolver and came back
      # as the url path unchanged - a backslash path the harness then refused to build.
      path = Utils.fs_path(path)

      if path.start_with?('./', '../')
        raise ArgumentError, '`path` must be an absolute file system or URL path'
      end

      # A new mapping generation forgets cached resolutions (#154): polled here too, so a path
      # resolved before an install does not keep its old URL when no Builder is made after it.
      generation

      # Caches the manifest key, not its value, so a manifest loaded or reset later is still
      # honoured. Every string is frozen: the URL path is handed back to callers, and in the
      # Rails.root branch it is the key itself, so mutating it would redirect later lookups.
      key, url_path, abs_path = resolved[path] ||= entry_for(path).map(&:-@).freeze
      manifest_path = Proscenium::Manifest[key]

      as_array ? [manifest_path, url_path, abs_path] : manifest_path || url_path
    end

    # The manifest key, URL path and absolute file system path for `path`. In the gem branch the
    # key differs from the URL path, so it is kept rather than derived.
    def self.entry_for(path)
      if (vpath = BundledGems.virtual_path(path))
        [vpath, "/node_modules/#{vpath}", path]
      elsif path.start_with?("#{Rails.root}/")
        vpath = path.delete_prefix(Rails.root.to_s)
        [vpath, vpath, path]
      else
        [path, *Builder.resolve(path)]
      end
    end
    private_class_method :entry_for

    # The mapping generation builds and resolutions use now (#154). Development and test start a
    # new one when the files the context map is built from change, and forget resolved paths with
    # it; production keeps one for the process. Here rather than on Builder, which loads the Go
    # library when first referenced, so resolving a path never needs it.
    def self.generation
      return 0 if Rails.env.production?

      number, changed = MappingGeneration.refresh(ContextMap.project_root)
      reset if changed
      number
    end

    def self.reset
      self.resolved = {}
    end
  end
end
