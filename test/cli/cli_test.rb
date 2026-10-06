# frozen_string_literal: true

require_relative 'helper'
require 'open3'
require 'rbconfig'

describe Proscenium::CLI do
  include CLIHelper

  it 'prints its version' do
    assert_equal [0, "#{Proscenium::VERSION}\n", ''], cli('--version')
  end

  it 'prints its version as a JSON event' do
    status, out, = cli('--version', '--json')

    assert_equal 0, status
    version = Proscenium::VERSION

    assert_equal({ 'schema' => 1, 'event' => 'version', 'status' => 'ok', 'message' => version,
                   'details' => { 'version' => version } }, JSON.parse(out))
  end

  it 'prints usage with no command' do
    status, out, = cli

    assert_equal 0, status
    assert_includes out, 'Usage: bundle exec proscenium'
  end

  it 'answers to psm, as the same command' do
    lib = File.expand_path('../../lib', __dir__)
    out, status = Open3.capture2e(RbConfig.ruby, '-I', lib,
                                  File.expand_path('../../exe/psm', __dir__), '--help')

    assert_predicate status, :success?, out
    assert_includes out, 'bundle exec psm <command>'
  end

  it 'prints the usage, with the install options, for --help after a command' do
    [%w[install --help], %w[gem check --help], %w[inspect -h]].each do |argv|
      status, out, = cli(*argv)

      assert_equal 0, status, argv.join(' ')
      assert_includes out, '--production', argv.join(' ')
    end
  end

  # --quiet quietens progress, not a command whose output is its result.
  it 'still prints the version and the usage with --quiet' do
    assert_equal [0, "#{Proscenium::VERSION}\n"], cli('--version', '--quiet').first(2)
    assert_includes cli('--help', '--quiet')[1], 'Usage: bundle exec proscenium'
    event = JSON.parse(cli('--version', '--json', '--quiet')[1])

    assert_equal ['ok', Proscenium::VERSION], [event['status'], event['message']]
  end

  it 'refuses --js-arg with --frozen or --offline, an unknown flag, and an unknown gem command' do
    # `install frozen`, a positional argument install does not take, must not run a full install.
    [%w[install --frozen --js-arg --x], %w[install --offline --js-arg --x], %w[install --bogus],
     %w[install frozen], %w[gem frobnicate]].each do |argv|
      status, out, err = cli(*argv)

      assert_equal [2, ''], [status, out], argv.join(' ')
      assert_includes err, 'PSM-E-USAGE', argv.join(' ')
    end
  end

  it 'runs inspect as doctor too, with its gem' do
    new = Proscenium::CLI::Inspect.method(:new)
    seen = []
    Proscenium::CLI::Inspect.define_singleton_method(:new) do |_root, _reporter, gem:|
      seen << gem
      Struct.new(:call).new(42)
    end

    assert_equal [42, 42], [cli('doctor').first, cli('doctor', 'hue').first]
    assert_equal [nil, 'hue'], seen
    assert_includes cli('--help')[1], 'doctor [gem]'
  ensure
    Proscenium::CLI::Inspect.define_singleton_method(:new, new)
  end

  it 'refuses an unknown command with exit 2' do
    status, out, err = cli('frobnicate')

    assert_equal 2, status
    assert_empty out
    assert_includes err, 'Error: Unknown command: frobnicate'
    assert_includes err, '(PSM-E-USAGE)'
  end

  it 'reports an unexpected error as an internal error, exit 1, with a bug-report hint' do
    run = Proscenium::CLI.method(:run)
    Proscenium::CLI.define_singleton_method(:run) { |*| raise ArgumentError, 'boom' }
    status, _, err = cli('--version')

    assert_equal 1, status
    assert_includes err, 'Error: Something went wrong inside Proscenium: ArgumentError: boom'
    assert_includes err, '(PSM-E-INTERNAL)'
    assert_includes err, 'github.com/joelmoss/proscenium/issues'
  ensure
    Proscenium::CLI.define_singleton_method(:run, run)
  end
end
