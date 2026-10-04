# frozen_string_literal: true

require_relative 'helper'

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

  it 'refuses an unknown command with exit 2' do
    status, out, err = cli('frobnicate')

    assert_equal 2, status
    assert_empty out
    assert_includes err, 'PSM-E-USAGE: Unknown command: frobnicate'
  end

  it 'reports an unexpected error as an internal error, exit 1, with a bug-report hint' do
    run = Proscenium::CLI.method(:run)
    Proscenium::CLI.define_singleton_method(:run) { |*| raise ArgumentError, 'boom' }
    status, _, err = cli('--version')

    assert_equal 1, status
    assert_includes err, 'PSM-E-INTERNAL: Unexpected error: ArgumentError: boom'
    assert_includes err, 'github.com/joelmoss/proscenium/issues'
  ensure
    Proscenium::CLI.define_singleton_method(:run, run)
  end
end
