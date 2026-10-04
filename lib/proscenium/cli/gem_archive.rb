# frozen_string_literal: true

require 'rubygems/package'
require 'zlib'
require_relative '../bundled_gems'
require_relative 'rules'

module Proscenium
  module CLI
    # A built gem's specification and package.json, read from its archive without unpacking it
    # (#154). Nothing is extracted, so no entry name can write anywhere, and the manifest entry is
    # read only if it is a regular file within the size limit (C29).
    module GemArchive
      module_function

      # [spec, manifest text or nil, why it could not be read or nil].
      def read(path)
        spec = Gem::Package.new(path).spec
        root = BundledGems.frontend_root(spec) || ''
        wanted = root.empty? ? 'package.json' : File.join(root, 'package.json')
        manifest = cause = nil
        File.open(path, 'rb') do |io|
          Gem::Package::TarReader.new(io).each do |entry|
            next unless entry.full_name == 'data.tar.gz'

            Zlib::GzipReader.wrap(entry) do |gz|
              Gem::Package::TarReader.new(gz).each do |file|
                manifest, cause = manifest_entry(file) if file.full_name == wanted
              end
            end
          end
        end
        [spec, manifest, cause]
      end

      def manifest_entry(entry)
        return [nil, 'it is not a regular file'] unless entry.file?
        return [nil, 'it is larger than 1 MB'] if entry.header.size > Rules::MANIFEST_LIMIT

        [entry.read, nil]
      end
    end
  end
end
