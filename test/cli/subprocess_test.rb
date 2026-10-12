# frozen_string_literal: true

require_relative 'helper'
require_relative '../support/subprocess'
require 'rbconfig'

# The deadline every test subprocess runs under: a hang fails its test, not the CI job.
describe Subprocess do
  it 'returns the output and status of a command that finishes' do
    out, err, status = Subprocess.capture(RbConfig.ruby, '-e', 'print 1; warn 2')

    assert_equal ['1', "2\n", true], [out, err, status.success?]
  end

  it 'kills a command that outlives its deadline, and fails naming it' do
    started = Time.now
    error = assert_raises(RuntimeError) do
      Subprocess.capture(RbConfig.ruby, '-e', 'puts :started; $stdout.flush; sleep 30', timeout: 1)
    end

    assert_operator Time.now - started, :<, 10
    assert_match(/did not finish in 1s. It printed:\nstarted/, error.message)
  end
end
