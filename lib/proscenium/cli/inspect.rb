# frozen_string_literal: true

require 'json'
require 'bundler'
require_relative '../bundled_gems'
require_relative 'contexts'
require_relative 'manager'

module Proscenium
  module CLI
    # `proscenium inspect [gem]` (#154): read-only. What each participating gem contributes, where
    # it is locked from, whether its committed context is current, and which gems ship a
    # package.json without taking part. With --json, one document.
    class Inspect
      CREDENTIALS = %r{(://)[^/@\s]+@}

      def initialize(root, reporter, gem: nil)
        @root = root
        @reporter = reporter
        @only = gem
      end

      def call
        report = build
        if @reporter.json?
          @reporter.document(report)
        else
          @reporter.info(text(report), event: 'inspect')
        end
        0
      end

      private

      def build
        overrides = BundledGems.overrides(@root)
        specs = BundledGems.installed_specs
        participating = BundledGems.participating(specs, overrides:)
        if @only && !participating.key?(@only)
          raise Error.new('PSM-E-USAGE', detail: "#{@only} does not take part in JavaScript " \
                                                 'dependency installation')
        end

        contexts = Contexts.new(@root, participating)
        committed = Contexts.committed(@root)
        gems = participating.keys.select { @only.nil? || it == @only }.map do |name|
          gem_report(name, participating[name], contexts, committed)
        end
        { 'schema' => 1, 'manager' => manager_report, 'gems' => gems,
          'notParticipating' => BundledGems.unparticipating_with_manifest(specs, overrides:),
          'problems' => contexts.problems.map { |code, args| Error.new(code, **args).message } }
      rescue BundledGems::ConfigError => e
        raise Error.new('PSM-E-CONFIG', detail: e.message)
      end

      def gem_report(name, spec, contexts, committed)
        context = contexts.contexts[name]
        current = context && JSON.parse(context.json)
        path = committed[name]
        on_disk = path && File.exist?(path) ? File.read(path) : nil
        {
          'gem' => name, 'version' => spec.version.to_s, 'source' => redact(source(name)),
          'context' => ".proscenium/packages/#{name}",
          'status' => status(context, on_disk),
          'projectionSha256' => current&.dig('proscenium', 'projectionSha256'),
          'kept' => current ? (current.keys & DependencyContext::FIELDS) : [],
          'gitAndUrl' => (context&.git_and_url || []).map { redact(it) },
          'optionalPeers' => optional_peers(current)
        }
      end

      def status(context, on_disk)
        return 'invalid' unless context
        return 'missing' unless on_disk

        on_disk == context.json ? 'current' : 'stale'
      end

      # Where Gemfile.lock takes the gem from.
      def source(name)
        locked = Bundler.locked_gems&.specs&.find { it.name == name }
        return 'not locked' unless locked

        locked.source.to_s
      end

      # Optional peers that are other gems, beside the version Bundler locked: Bundler checks a
      # gemspec dependency's version, but nothing checks an optional peer's range.
      def optional_peers(context)
        return [] unless context

        (context['peerDependenciesMeta'] || {}).filter_map do |name, meta|
          next unless meta.is_a?(Hash) && meta['optional'] && name.start_with?('@rubygems/')

          gem = name.delete_prefix('@rubygems/')
          locked = Bundler.locked_gems&.specs&.find { it.name == gem }
          { 'peer' => name, 'range' => context.dig('peerDependencies', name),
            'locked' => locked&.version&.to_s }
        end
      end

      def manager_report
        manager = Manager.select(@root)
        linker = manager.name == 'bun' ? manager.bun_linker : pnpm_linker
        { 'name' => manager.name, 'linker' => linker }
      rescue Error
        nil
      end

      # pnpm's `node-linker` from .npmrc, `isolated` by default.
      def pnpm_linker
        npmrc = File.join(@root, '.npmrc')
        setting = File.exist?(npmrc) && File.read(npmrc)[/^\s*node-linker\s*=\s*(\S+)/, 1]
        setting || 'isolated'
      end

      def redact(text) = text.to_s.gsub(CREDENTIALS, '\1<redacted>@')

      def text(report)
        lines = []
        if (manager = report['manager'])
          lines << "Manager: #{manager['name']} (#{manager['linker'] || 'linker not set'})"
        end
        report['gems'].each do |gem|
          lines << "#{gem['gem']} #{gem['version']}: context #{gem['status']}"
          lines << "  source: #{gem['source']}"
          lines << "  keeps: #{gem['kept'].join(', ')}" if gem['kept'].any?
          if gem['gitAndUrl'].any?
            lines << "  Git and URL dependencies: #{gem['gitAndUrl'].join(', ')}"
          end
          gem['optionalPeers'].each do |peer|
            locked = peer['locked'] || 'none'
            lines << "  optional peer #{peer['peer']} #{peer['range']} (locked: #{locked})"
          end
        end
        lines << 'No gems take part.' if report['gems'].empty?
        if report['notParticipating'].any?
          names = report['notParticipating'].join(', ')
          lines << "Ship a package.json but do not take part: #{names}"
        end
        report['problems'].each { lines << "Problem: #{it}" }
        lines.join("\n")
      end
    end
  end
end
