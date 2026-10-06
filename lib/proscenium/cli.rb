# frozen_string_literal: true

require_relative 'version'
require_relative 'cli/error'
require_relative 'cli/reporter'
require_relative 'cli/gem_check'
require_relative 'cli/install'
require_relative 'cli/inspect'

autoload :OptionParser, 'optparse'

module Proscenium
  # The `proscenium` command (#154): installs participating gems' JavaScript dependencies through
  # the app's own package manager. It runs under `bundle exec` and reads the bundle in process.
  #
  # Load isolation is a contract, tested in test/cli/load_isolation_test.rb: nothing under
  # lib/proscenium/cli/ may require `proscenium` itself, ActiveSupport, Rails, FFI or the engine
  # library. Only Proscenium's plain-Ruby modules the engine shares with it (bundled_gems,
  # dependency_context, context_map, stale_contexts) and these files.
  module CLI
    USAGE = <<~TEXT
      Usage: bundle exec proscenium <command> [options]

      Installs the NPM dependencies of the gems in your bundle that opt in.

      Commands:
        install            Install your gems' NPM dependencies
        install --frozen   Check everything is up to date, without changing anything you commit
        inspect [gem]      Show which gems install NPM dependencies, and any problems
        doctor [gem]       The same as inspect
        gem check [path]   For gem authors: check a gem's package.json and gemspec

      install options:
        --frozen                        Change nothing you commit; fail if anything is out of date
        --production                    Leave out development dependencies, and keep the committed
                                        dependency context of a gem in an excluded Bundler group
        --offline                       Install from the package manager's cache only
        --manager pnpm|bun              Which package manager, for an app with no package.json yet
        --js-arg ARG                    Pass ARG to the package manager (repeatable)
        --experimental-manager-version  Allow a package manager version Proscenium doesn't support

      Options:
        --json             Print newline-delimited JSON events instead of text
        --quiet            Print less
        --version          Print the Proscenium version
        --help             Print this help
    TEXT

    module_function

    # Runs the command in `argv` and returns its exit status.
    def start(argv, out: $stdout, err: $stderr)
      args = argv.dup
      reporter = Reporter.new(out:, err:, json: !args.delete('--json').nil?,
                              quiet: !args.delete('--quiet').nil?)
      run(args, reporter)
    rescue Error => e
      reporter.error(e)
      e.exit_status
    rescue Interrupt
      Error::EXIT.fetch(:interrupted)
    rescue StandardError => e
      internal = Error.new('PSM-E-INTERNAL', detail: "#{e.class}: #{e.message}")
      reporter.error(internal)
      internal.exit_status
    end

    def run(args, reporter)
      # Anywhere, so `install --help` and `gem check --help` print it too.
      if args.intersect?(%w[--help -h])
        reporter.result(USAGE, event: 'help')
        return 0
      end

      case args.first
      when '--version', '-v'
        reporter.result(Proscenium::VERSION, event: 'version', version: Proscenium::VERSION)
      when nil
        reporter.result(USAGE, event: 'help')
      when 'install'
        return Install.new(project_root, reporter, **install_options(args.drop(1))).call
      when 'inspect', 'doctor'
        return Inspect.new(project_root, reporter, gem: args[1]).call
      when 'gem'
        unless args[1] == 'check'
          raise Error.new('PSM-E-USAGE', detail: 'Did you mean `proscenium gem check`?')
        end

        return GemCheck.new(args[2], reporter).call
      else
        raise Error.new('PSM-E-USAGE', detail: "Unknown command: #{args.join(' ')}")
      end

      0
    end

    # The active bundle's root: subdirectories and BUNDLE_GEMFILE both resolve to the app the
    # bundle belongs to, so contexts are never written into another app.
    def project_root = Bundler.root.to_s

    def install_options(args)
      options = { js_args: [] }
      rest = OptionParser.new do |parser|
        parser.on('--frozen') { options[:frozen] = true }
        parser.on('--production') { options[:production] = true }
        parser.on('--offline') { options[:offline] = true }
        parser.on('--manager NAME') { options[:manager] = it }
        parser.on('--experimental-manager-version') { options[:experimental] = true }
        parser.on('--js-arg ARG') { options[:js_args] << it }
      end.parse(args)
      raise Error.new('PSM-E-USAGE', detail: "Unexpected argument: #{rest.join(' ')}") if rest.any?
      if options[:js_args].any? && (options[:frozen] || options[:offline])
        raise Error.new('PSM-E-USAGE', detail: '--js-arg cannot be used with --frozen or --offline')
      end

      options
    rescue OptionParser::ParseError => e
      raise Error.new('PSM-E-USAGE', detail: e.message)
    end
  end
end
