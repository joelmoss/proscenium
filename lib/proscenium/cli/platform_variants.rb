# frozen_string_literal: true

require 'json'
require_relative '../bundled_gems'
require_relative '../dependency_context'
require_relative 'gem_archive'

module Proscenium
  module CLI
    # A gem's platform variants must agree on JavaScript dependencies (#154, C33). The lock records
    # one set of dependencies per gem, whichever variant a host installs, so variants that
    # participate differently, or project different dependencies, are unsupported until a
    # profile-aware lock design exists. The other variants are read from the Bundler cache when
    # they are there; their frontend files may differ freely.
    module PlatformVariants
      module_function

      # Each [gem, variant archive name] in `cache` that differs from the installed variant in
      # `specs`.
      def differences(cache, specs)
        return [] unless Dir.exist?(cache)

        specs.flat_map do |spec|
          variants(cache, spec).filter_map do |file|
            variant, manifest, = GemArchive.read(file)
            next unless variant.name == spec.name && variant.full_name != spec.full_name

            [spec.name, File.basename(file)] if differs?(spec, variant, manifest)
          end
        end
      end

      def variants(cache, spec)
        Dir.glob(["#{spec.name}-#{spec.version}.gem", "#{spec.name}-#{spec.version}-*.gem"],
                 base: cache).map { File.join(cache, it) }
      end

      def differs?(spec, variant, manifest)
        opted_in = BundledGems.opted_in?(spec)
        return true if opted_in != BundledGems.opted_in?(variant)
        return false unless opted_in

        projection(spec.name, installed_manifest(spec)) != projection(spec.name, manifest)
      end

      def installed_manifest(spec)
        root = BundledGems.manifest_root(spec)
        path = root && File.join(root, 'package.json')
        path && File.file?(path) ? File.read(path) : nil
      end

      # The projection hash of a manifest's text, or nil for none that can be read.
      def projection(gem, text)
        manifest = text && JSON.parse(text)
        return nil unless manifest.is_a?(Hash)

        DependencyContext.project(gem, manifest).dig('proscenium', 'projectionSha256')
      rescue JSON::ParserError
        nil
      end
    end
  end
end
