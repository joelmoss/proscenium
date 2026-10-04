# frozen_string_literal: true

require 'json'
require 'rubygems/package'
require 'zlib'
require_relative 'gem_archive'
require_relative 'rules'
require_relative '../bundled_gems'

module Proscenium
  module CLI
    # `proscenium gem check [path]`: the gem author's check, which needs no bundle. Checks a gem
    # source directory, or a built `.gem`, against the author contract: opted in, the manifest and
    # frontend files in `spec.files`, and the manifest rules. Runs nothing the gem ships.
    class GemCheck
      FRONTEND = /\.(?:js|jsx|mjs|ts|tsx|css)\z/
      # Not shipped on purpose: tests and dependencies.
      UNSHIPPED = %r{(?:\A|/)(?:node_modules|test|spec)/|\.(?:test|spec)\.[a-z]+\z}

      def initialize(path, reporter)
        @path = File.expand_path(path || Dir.pwd)
        @reporter = reporter
      end

      def call
        spec, files, manifest_text, cause = @path.end_with?('.gem') ? read_archive : read_source
        problems = check(spec, files, manifest_text, cause)
        problems.each { |code, args| @reporter.error(Error.new(code, **args), phase: 'gem-check') }
        if problems.empty?
          @reporter.info("#{spec.name} #{spec.version} meets the Proscenium gem contract.",
                         event: 'gem-check', gem: spec.name)
          return 0
        end

        Error::EXIT.fetch(:input)
      end

      private

      # `cause` is why the manifest could not be read safely, if it could not (C29).
      def check(spec, files, manifest_text, cause = nil)
        gem = spec.name
        unless spec.metadata['proscenium.dependencies'] == 'true'
          return [['PSM-E-NOT-OPTED-IN', { gem: }]]
        end

        root = frontend_root(spec)
        return [['PSM-E-FRONTEND-ROOT', { gem:, root: }]] unless root

        manifest_path = root.empty? ? 'package.json' : File.join(root, 'package.json')
        return [['PSM-E-MANIFEST', { gem:, path: manifest_path, cause: }]] if cause
        unless manifest_text
          return [['PSM-E-MANIFEST',
                   { gem:, path: manifest_path, cause: 'it is missing' }]]
        end

        manifest = parse(manifest_text)
        if manifest.is_a?(String)
          return [['PSM-E-MANIFEST',
                   { gem:, path: manifest_path, cause: manifest }]]
        end

        problems = Rules.check(gem, manifest, root: source_root(root))
        unless files.include?(manifest_path)
          problems << ['PSM-E-GEM-FILES',
                       { gem:, files: manifest_path }]
        end
        missing = unlisted_frontend(files, root)
        problems << ['PSM-E-GEM-FILES', { gem:, files: summarize(missing) }] if missing.any?
        problems + cross_gem(spec, manifest)
      end

      def frontend_root(spec) = BundledGems.frontend_root(spec)

      # A reference to another gem's context needs that gem as a runtime dependency.
      def cross_gem(spec, manifest)
        runtime = spec.runtime_dependencies.map(&:name)
        Rules::DEPENDENCY_FIELDS.flat_map { (manifest[it] || {}).keys }
                                .grep(%r{\A@rubygems/})
                                .map { it.delete_prefix('@rubygems/') }
                                .reject { runtime.include?(it) }
                                .map { ['PSM-E-CROSS-GEM', { gem: spec.name, other: it }] }
      end

      def parse(text)
        manifest = JSON.parse(text)
        manifest.is_a?(Hash) ? manifest : 'it is not a JSON object'
      rescue JSON::ParserError => e
        "it is not valid JSON (#{e.message.lines.first.strip})"
      end

      def read_source
        gemspecs = Dir.glob('*.gemspec', base: @path)
        raise Error.new('PSM-E-GEMSPEC', path: @path, found: gemspecs.size) unless gemspecs.one?

        # Loaded by absolute path: Specification.load caches by the path it is given, so a relative
        # one would return another directory's gem. Inside the directory, because gemspecs often
        # list their files relative to it.
        spec = Dir.chdir(@path) { Gem::Specification.load(File.join(@path, gemspecs.first)) }
        raise Error.new('PSM-E-GEMSPEC', path: @path, found: 0) unless spec

        root = frontend_root(spec) || ''
        manifest = File.join(@path, root, 'package.json')
        @source = @path
        return [spec, spec.files, nil, nil] unless File.exist?(manifest)

        cause = Rules.manifest_file_problem(manifest, @path)
        [spec, spec.files, cause ? nil : File.read(manifest), cause]
      end

      # A built gem, read from its archive (GemArchive).
      def read_archive
        spec, manifest, cause = GemArchive.read(@path)
        [spec, spec.files, manifest, cause]
      end

      def source_root(root) = @source && File.join(@source, root)

      # Frontend files on disk under the frontend root but missing from `spec.files`. A built gem
      # has nothing on disk to compare.
      def unlisted_frontend(files, root)
        return [] unless @source

        Dir.glob('**/*', base: File.join(@source, root)).grep(FRONTEND)
           .map { root.empty? ? it : File.join(root, it) }
           .reject { files.include?(it) || UNSHIPPED.match?(it) }
      end

      def summarize(paths)
        shown = paths.first(3).join(', ')
        paths.size > 3 ? "#{shown} and #{paths.size - 3} more" : shown
      end
    end
  end
end
