# frozen_string_literal: true

# The CLI's own test helper. It loads the CLI and Minitest only, never test_helper.rb (which boots
# the dummy Rails app), so these tests exercise the CLI as `bundle exec proscenium` loads it.
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require 'maxitest/autorun'
require 'stringio'
require 'proscenium/cli'

module CLIHelper
  # Runs the CLI in process and returns its exit status, stdout and stderr.
  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = Proscenium::CLI.start(argv, out:, err:)
    [status, out.string, err.string]
  end
end
