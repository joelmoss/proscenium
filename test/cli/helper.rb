# frozen_string_literal: true

# The CLI's own test helper. It loads the CLI and Minitest only, never test_helper.rb (which boots
# the dummy Rails app), so these tests exercise the CLI as `bundle exec proscenium` loads it.
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require 'maxitest/autorun'
require 'stringio'
require 'proscenium/cli'

module CLIHelper
  # The pnpm an end-to-end fixture app pins in packageManager: the capability table's CI floor,
  # or PROSCENIUM_PNPM, which the nightly canary sets to a line's newest patch.
  def self.pnpm_version
    ENV.fetch('PROSCENIUM_PNPM') do
      Proscenium::CLI::Manager::CAPABILITIES.dig('managers', 'pnpm', 'lines', 0, 'ci')
    end
  end

  # Runs the CLI in process and returns its exit status, stdout and stderr.
  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    status = Proscenium::CLI.start(argv, out:, err:)
    [status, out.string, err.string]
  end
end
