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
      Subprocess.capture(RbConfig.ruby, '-e', 'puts :started; $stdout.flush; sleep 30', timeout: 5)
    end

    assert_operator Time.now - started, :<, 15
    assert_match(/did not finish in 5s. It printed:\nstarted/, error.message)
  end

  # Value: protects=output going to files, so a command that writes more than a pipe holds still
  # finishes; fails_when=capture goes back to pipes nobody drains while it polls; why_new=the
  # short outputs above fit a pipe either way; seam=none; no_claim=says nothing of Windows
  it 'returns more output than a pipe holds' do
    out, _, status = Subprocess.capture(RbConfig.ruby, '-e', '$stdout.write "x" * 1_000_000',
                                        timeout: 20)

    assert_predicate status, :success?
    assert_equal 1_000_000, out.size
  end

  # Value: protects=a timeout killing the command's whole tree, as `bun test` and its Rails daemon
  # are; fails_when=the kill reaches only the child, not its group; why_new=the timeout test above
  # has no grandchild; seam=none; no_claim=says nothing of taskkill on Windows
  it 'kills what a command that outlived its deadline started' do
    skip 'Process.kill(0) cannot tell whether taskkill ended a Windows process' if Gem.win_platform?

    script = 'pid = Process.spawn(RbConfig.ruby, "-e", "sleep 30"); puts pid; $stdout.flush; ' \
             'sleep 30'
    error = assert_raises(RuntimeError) do
      Subprocess.capture(RbConfig.ruby, '-e', script, timeout: 5)
    end
    grandchild = error.message[/printed:\n(\d+)/, 1].to_i

    assert_predicate grandchild, :positive?, error.message
    # Killed at once, but reaped by init a moment later: until then the pid still answers.
    gone = 50.times.any? do
      Process.kill(0, grandchild)
      sleep 0.1
      false
    rescue Errno::ESRCH
      true
    end

    assert gone, "the grandchild #{grandchild} outlived the deadline"
  end
end
