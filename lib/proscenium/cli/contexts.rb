# frozen_string_literal: true

require 'json'
require_relative '../bundled_gems'
require_relative '../dependency_context'
require_relative 'rules'

module Proscenium
  module CLI
    # The contexts the bundle calls for (#154): one per participating, installed gem, projected
    # from its package.json after the author contract and the gem-to-gem rules. Computes; never
    # writes.
    class Contexts
      DIR = File.join('.proscenium', 'packages')
      ESCAPE = "To stop installing %<gem>s's JavaScript dependencies, add " \
               '`"gemOverrides": {"%<gem>s": {"participate": false}}` to proscenium.json; ' \
               'the app must then declare them itself.'

      # A gem's context: its JSON text, and the Git and URL dependencies it introduces.
      Context = Struct.new(:gem, :json, :git_and_url, keyword_init: true)

      attr_reader :contexts, :problems, :warnings

      # `specs` are the participating installed specs by name; `root` is the app.
      def initialize(root, specs)
        @root = root
        @specs = specs
        @contexts = {}
        @problems = []
        @warnings = []
        specs.each_value { add(it) }
      end

      def ok? = @problems.empty?

      # The committed context directories under the app, by gem name.
      def self.committed(root)
        dir = File.join(root, DIR)
        return {} unless Dir.exist?(dir)

        Dir.children(dir).select { File.directory?(File.join(dir, it)) }.sort
           .to_h { [it, File.join(dir, it, 'package.json')] }
      end

      private

      def add(spec)
        gem = spec.name
        manifest_root = BundledGems.manifest_root(spec)
        unless manifest_root
          return problem('PSM-E-FRONTEND-ROOT', gem:,
                                                root: spec.metadata['proscenium.frontend_root'])
        end

        manifest = read_manifest(gem, manifest_root, spec.full_gem_path) or return
        fatal = Rules.check(gem, manifest, root: manifest_root)
        react, fatal = fatal.partition { it.first == 'PSM-E-REACT' }
        @warnings.concat(react)
        fatal.each { |code, args| problem(code, **args) }
        return unless fatal.empty?

        manifest = link_gems(gem, spec, manifest) or return
        context = DependencyContext.project(gem, manifest)
        @contexts[gem] = Context.new(gem:, json: DependencyContext.to_json(context),
                                     git_and_url: git_and_url(context))
      end

      def read_manifest(gem, manifest_root, gem_root)
        path = File.join(manifest_root, 'package.json')
        unless File.exist?(path)
          return problem('PSM-E-MANIFEST', gem:, path: 'package.json', cause: 'it is missing')
        end
        if (cause = Rules.manifest_file_problem(path, gem_root))
          return problem('PSM-E-MANIFEST', gem:, path: 'package.json', cause:)
        end

        manifest = JSON.parse(File.read(path))
        return manifest if manifest.is_a?(Hash)

        problem('PSM-E-MANIFEST', gem:, path: 'package.json', cause: 'it is not a JSON object')
      rescue JSON::ParserError
        problem('PSM-E-MANIFEST', gem:, path: 'package.json', cause: 'it is not valid JSON')
      end

      # Rewrites references to other gems' contexts to `workspace:*`. A reference is kept only if
      # the gemspec depends on the other gem and that gem participates: Bundler then guarantees it
      # is locked at a compatible version. An optional peer whose gem does not participate is left
      # out, as an absent optional peer would be.
      def link_gems(gem, spec, manifest)
        runtime = spec.runtime_dependencies.map(&:name)
        optional = (manifest['peerDependenciesMeta'] || {}).select do |_, meta|
          meta.is_a?(Hash) && meta['optional']
        end.keys
        ok = true
        linked = Rules::DEPENDENCY_FIELDS.to_h do |field|
          deps = (manifest[field] || {}).filter_map do |name, version|
            next [name, version] unless name.start_with?('@rubygems/')

            other = name.delete_prefix('@rubygems/')
            participates = @specs.key?(other)
            if field == 'peerDependencies' && optional.include?(name) && !participates
              nil
            elsif !runtime.include?(other)
              ok = false
              problem('PSM-E-CROSS-GEM', gem:, other:)
            elsif !participates
              ok = false
              problem('PSM-E-CROSS-GEM-TARGET', gem:, other:)
            else
              [name, 'workspace:*']
            end
          end
          [field, deps.to_h]
        end
        ok ? manifest.merge(linked) : nil
      end

      def git_and_url(context)
        Rules::DEPENDENCY_FIELDS.flat_map { (context[it] || {}).to_a }
                                .select { |_, spec| spec.to_s.match?(%r{\A(?:github:|git\+|https://)}) }
                                .map { |name, spec| "#{name}@#{spec}" }
      end

      # Records a problem with the gem's own manifest, with the consumer's way out. Returns nil,
      # so a caller can `return problem(...)` to stop.
      def problem(code, **args)
        @problems << [code, args.merge(escape: format(ESCAPE, gem: args.fetch(:gem)))]
        nil
      end
    end
  end
end
