# frozen_string_literal: true

require_relative 'version'
require_relative 'cli/error'
require_relative 'cli/reporter'
require_relative 'cli/gem_check'
require_relative 'cli/install'

autoload :OptionParser, 'optparse'

module Proscenium
  # The `proscenium` command (#154): installs participating gems' JavaScript dependencies through
  # the app's own package manager. It runs under `bundle exec` and reads the bundle in process.
  #
  # Load isolation is a contract, tested in test/cli/load_isolation_test.rb: nothing under
  # lib/proscenium/cli/ may require `proscenium` itself, ActiveSupport, Rails, FFI or the engine
  # library. Only `proscenium/bundled_gems` and these files.
  module CLI
    USAGE = <<~TEXT
      Usage: bundle exec proscenium <command> [options]

      Commands:
        install            Install participating gems' JavaScript dependencies
        install --frozen   Check everything is up to date, writing nothing
        inspect [gem]      Show participating gems and their contexts
        gem check [path]   Check a gem's package.json and gemspec (needs no bundle)

      Options:
        --json             Newline-delimited JSON events on stdout
        --quiet            Less output
        --version          Print the Proscenium version
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
      case args.first
      when '--version', '-v'
        reporter.info(Proscenium::VERSION, event: 'version', version: Proscenium::VERSION)
      when '--help', '-h', nil
        reporter.info(USAGE, event: 'help')
      when 'install'
        return Install.new(project_root, reporter, **install_options(args.drop(1))).call
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
      OptionParser.new do |parser|
        parser.on('--frozen') { options[:frozen] = true }
        parser.on('--production') { options[:production] = true }
        parser.on('--offline') { options[:offline] = true }
        parser.on('--manager NAME') { options[:manager] = it }
        parser.on('--experimental-manager-version') { options[:experimental] = true }
        parser.on('--js-arg ARG') { options[:js_args] << it }
      end.parse!(args.dup)
      if options[:js_args].any? && (options[:frozen] || options[:offline])
        raise Error.new('PSM-E-USAGE', detail: '--js-arg cannot be used with --frozen or --offline')
      end

      options
    rescue OptionParser::ParseError => e
      raise Error.new('PSM-E-USAGE', detail: e.message)
    end
  end
end
