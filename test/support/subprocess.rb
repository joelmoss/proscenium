# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# Runs a command for a test, with a deadline. Plain Ruby, so the CLI's tests, which never boot
# Rails, can use it as well as the engine's.
module Subprocess
  TIMEOUT = 180

  module_function

  # The command's stdout, stderr and status, or a failure naming it once it has run for `timeout`
  # seconds: a hang on one host fails its test rather than the whole CI job. Output goes to files,
  # not pipes: `bun test` and its Rails daemon write a lot, and on Windows a pipe nobody drains in
  # time fills and blocks them for good. The process is polled, so nothing waits on it, and on
  # timeout its whole tree is killed and the failure carries what it had printed.
  def capture(*command, env: {}, chdir: Dir.pwd, timeout: TIMEOUT)
    dir = Dir.mktmpdir('subprocess')
    begin
      out, err = %w[out err].map { File.join(dir, it) }
      pid = Process.spawn(env, *command, chdir:, in: File::NULL, out:, err:,
                                         **(Gem.win_platform? ? {} : { pgroup: true }))
      deadline = Time.now + timeout
      nil
      sleep 0.1 until (status = Process.wait2(pid, Process::WNOHANG)&.last) || Time.now > deadline
      unless status
        kill_tree(pid)
        raise "#{command.first(3).join(' ')} did not finish in #{timeout}s. It printed:\n" \
              "#{File.read(out)}#{File.read(err)}"
      end

      [File.read(out), File.read(err), status]
    ensure
      # rm_rf ignores a file still open: `bun test`'s Rails daemon outlives it for a moment,
      # holding the output files, and Windows will not delete an open file.
      FileUtils.rm_rf(dir)
    end
  end

  def kill_tree(pid)
    if Gem.win_platform?
      system('taskkill', '/T', '/F', '/PID', pid.to_s, out: File::NULL, err: File::NULL)
    else
      Process.kill(:KILL, -pid)
    end
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
