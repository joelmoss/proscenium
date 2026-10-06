# frozen_string_literal: true

require 'json'
require 'bundler'
require_relative '../bundled_gems'
require_relative 'contexts'
require_relative 'gitignore'
require_relative 'manager'
require_relative 'registration'
require_relative 'verify'
require_relative '../stale_contexts'

module Proscenium
  module CLI
    # `proscenium inspect [gem]` (#154): read-only. What each participating gem contributes, where
    # it is locked from, whether its committed context is current, and which gems ship a
    # package.json without taking part. With --json, one document.
    class Inspect
      CREDENTIALS = %r{(://)[^/@\s]+@}
      # A query parameter whose name says it holds a secret, which Bundler keeps in a git source.
      SECRET_PARAMS = /([?&][^=&#\s]*(?:token|key|auth|pass|secret|sig)[^=&#\s]*=)[^&#\s]+/i

      # Each context status, as a person reads it.
      STATUS = {
        'current' => ['up to date', :green],
        'stale' => ['out of date: run `bundle exec proscenium install`', :yellow],
        'edited' => ['edited by hand: run `bundle exec proscenium install` to restore it', :yellow],
        'missing' => ['not written yet: run `bundle exec proscenium install`', :yellow],
        'invalid' => ["can't be installed: see the problems below", :red]
      }.freeze

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
          @reporter.result(text(report), event: 'inspect')
        end
        report['problems'].empty? && report['buildRefused'].empty? ? 0 : Error::EXIT.fetch(:drift)
      end

      private

      def build
        overrides = BundledGems.overrides(@root)
        specs = BundledGems.installed_specs
        participating = BundledGems.participating(specs, overrides:)
        if @only && !participating.key?(@only)
          raise Error.new('PSM-E-USAGE', detail: "#{@only} doesn't install NPM " \
                                                 'dependencies through Proscenium')
        end

        contexts = Contexts.new(@root, participating)
        committed = Contexts.committed(@root)
        gems = participating.keys.select { @only.nil? || it == @only }.map do |name|
          gem_report(name, participating[name], contexts, committed)
        end
        manager, problems = select_manager
        # An app that uses none of this has nothing to set up, whatever its manager.
        if participating.any? || committed.any? || ContextMap.registrar(@root)
          problems += project_problems(manager, contexts, committed)
        else
          problems = []
        end
        problems += contexts.problems.map { |code, args| Error.new(code, **args) }
        { 'schema' => 1, 'manager' => manager_report(manager), 'gems' => gems,
          'notParticipating' => BundledGems.unparticipating_with_manifest(specs, overrides:),
          # Every reason the engine refuses to build: orphans and split peers as well.
          'buildRefused' => StaleContexts.problems(@root, specs),
          'problems' => problems.map { problem_report(it) } }
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
          'status' => status(context, on_disk, path),
          'projectionSha256' => current&.dig('proscenium', 'projectionSha256'),
          'kept' => current ? (current.keys & DependencyContext::FIELDS) : [],
          'gitAndUrl' => (context&.git_and_url || []).map { redact(it) },
          'optionalPeers' => optional_peers(current)
        }
      end

      # `stale` exactly when the engine refuses to build: the projection hash differs. Different
      # bytes with the same hash are a hand edit, which only `install --frozen` refuses.
      def status(context, on_disk, path)
        return 'invalid' unless context
        return 'missing' unless on_disk
        return 'current' if on_disk == context.json

        reason = StaleContexts.compare(context, path)
        reason.nil? || reason == StaleContexts::EDITED ? 'edited' : 'stale'
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

      # The manager, and what stops install using it, as install would check it: [manager or nil,
      # problems].
      def select_manager
        manager = Manager.select(@root)
        manager.check_version!
        manager.check_project!(frozen: Registration.registered?(@root, manager.name))
        [manager, []]
      rescue Error => e
        [manager, [e]]
      end

      # What stops the app's gem dependencies working once installed: the registration, the
      # .gitignore lines, the lockfile and the install itself. Before the first install, only that
      # it has not happened.
      def project_problems(manager, contexts, committed)
        return gitignore_problems unless manager

        file = manager.name == 'bun' ? 'package.json' : 'pnpm-workspace.yaml'
        registered = Registration.registered?(@root, manager.name)
        unregistered = Error.new('PSM-E-NOT-REGISTERED', file:, manager: manager.name)
        return [unregistered] if !registered && committed.empty?

        found = gitignore_problems
        found << unregistered unless registered
        lockfile = Manager::LOCKFILES.key(manager.name)
        lock = File.join(@root, lockfile)
        return found << Error.new('PSM-E-LOCKFILE-MISSING', lockfile:) unless File.exist?(lock)
        unless File.directory?(File.join(@root, 'node_modules'))
          return found << Error.new('PSM-E-NOT-INSTALLED')
        end

        found + (registered ? installed_problems(manager, contexts, File.read(lock)) : [])
      end

      def gitignore_problems
        path = File.join(@root, '.gitignore')
        text = File.exist?(path) ? File.read(path) : ''
        Gitignore.splice(text) == text ? [] : [Error.new('PSM-E-GITIGNORE')]
      end

      # A gem context the lock takes from a registry, or one the manager did not install. A split
      # peer is in buildRefused, as the engine refuses to build for it.
      def installed_problems(manager, contexts, lock)
        verify = Verify.new(@root, manager, contexts.contexts.keys)
        %i[check_registry check_workspaces].filter_map do |check|
          verify.public_send(check, lock)
          nil
        rescue Error => e
          e
        end
      end

      def problem_report(error)
        { 'code' => error.code, 'message' => error.message,
          'fix' => error.fix }
      end

      def manager_report(manager)
        return nil unless manager

        linker = manager.name == 'bun' ? manager.bun_linker : pnpm_linker
        { 'name' => manager.name, 'linker' => linker }
      end

      # pnpm's `node-linker` from .npmrc, `isolated` by default.
      def pnpm_linker
        npmrc = File.join(@root, '.npmrc')
        setting = File.exist?(npmrc) && File.read(npmrc)[/^\s*node-linker\s*=\s*(\S+)/, 1]
        setting || 'isolated'
      end

      def redact(text)
        text.to_s.gsub(CREDENTIALS, '\1<redacted>@').gsub(SECRET_PARAMS, '\1<redacted>')
      end

      def text(report)
        lines = []
        if (manager = report['manager'])
          linker = manager['linker'] ? "#{manager['linker']} linker" : 'linker not set'
          lines << "#{bold('Package manager:')} #{manager['name']} (#{linker})" << ''
        end
        lines.concat(gem_lines(report['gems']))
        if report['notParticipating'].any?
          lines << '' << bold('These gems ship a package.json but have not opted in:')
          lines.concat(report['notParticipating'].map { "  #{it}" })
          lines << '  To opt one in, add `"proscenium": {"gemOverrides": {"<gem>": ' \
                   '{"participate": true}}}` to package.json.'
        end
        report['problems'].each do |problem|
          lines << '' << "#{@reporter.paint('Problem:', :bold, :red)} #{problem['message']}"
          lines << "#{bold('To fix:')} #{problem['fix']}"
        end
        if report['buildRefused'].any?
          lines << '' << @reporter.paint('Rails will refuse to build assets until you fix:', :bold,
                                         :red)
          lines.concat(report['buildRefused'].map { "  - #{it}" })
        end
        if report['problems'].empty? && report['buildRefused'].empty?
          lines << '' << @reporter.paint('No problems found.', :bold, :green)
        end
        lines.join("\n")
      end

      def gem_lines(gems)
        return ['No gems install NPM dependencies through Proscenium.'] if gems.empty?

        lines = [bold("Gems whose NPM dependencies Proscenium installs (#{gems.size}):")]
        gems.each do |gem|
          status, colour = STATUS.fetch(gem['status'])
          lines << "  #{gem['gem']} #{gem['version']}: #{@reporter.paint(status, colour)}"
          lines << "    from: #{gem['source']}"
          lines << "    uses: #{gem['kept'].join(', ')}" if gem['kept'].any?
          if gem['gitAndUrl'].any?
            lines << "    Git and URL dependencies: #{gem['gitAndUrl'].join(', ')}"
          end
          gem['optionalPeers'].each do |peer|
            locked = peer['locked'] ? "#{peer['locked']} is locked" : 'not locked'
            lines << "    optional peer #{peer['peer']} #{peer['range']} (#{locked})"
          end
        end
        lines
      end

      def bold(text) = @reporter.paint(text, :bold)
    end
  end
end
