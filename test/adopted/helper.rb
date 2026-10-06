# frozen_string_literal: true

require_relative '../cli/helper'
require 'json'
require 'open3'
require 'tmpdir'
require 'rbconfig'
require_relative '../package_manager/stage_a/bundle'

# fixtures/adopted, an app that has adopted gem dependency contexts (#154, Stage C), driven as a
# subprocess: its own Gemfile sets Bundler.root, which the engine reads contexts from, and this
# suite's own bundle (or an Appraisal gemfile) would set it elsewhere.
#
# Runs only with STAGE_A=1: setting it up runs pnpm, as the stage-a CI job can.
module Adopted
  ROOT = File.expand_path('../../fixtures/adopted', __dir__)

  module_function

  def env
    # Frozen, so installing never rewrites the committed lock, and Bundler checks every gem
    # against the checksums it holds.
    env = { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'RAILS_ENV' => 'test',
            'BUNDLE_FROZEN' => 'true' }
    # CI installs gems into a bundle path; the fixture's gems are the same versions.
    path = Bundler.settings[:path]
    env['BUNDLE_PATH'] = File.expand_path(path, Bundler.root) if path
    env
  end

  # Installs the fixture's gems and runs a frozen native install, once per process: a fresh
  # checkout of an adopted app needs nothing else (C45). stage_a_widget_b is an archive gem in
  # vendor/cache, as a registry would serve it. It is committed rather than built here: RubyGems
  # versions build different bytes, and Gemfile.lock holds its checksum.
  def setup!
    @setup ||= begin
      gem = File.join(ROOT, 'vendor/cache/stage_a_widget_b-1.0.0.gem')
      raise "#{gem} is committed, and its checksum is in Gemfile.lock" unless File.exist?(gem)

      sh('bundle', 'install', '--local', '--quiet')
      sh('pnpm', 'install', '--frozen-lockfile')
      true
    end
  end

  def sh(*command)
    out, err, status = capture(*command)
    raise "#{command.join(' ')} failed:\n#{out}#{err}" unless status.success?

    out + err
  end

  # A command's stdout, stderr and status, or a failure naming it once it has run for TIMEOUT
  # seconds: a hang on one host fails its test rather than the whole CI job. Output goes to
  # files, not pipes: `bun test` and its Rails daemon write a lot, and on Windows a pipe nobody
  # drains in time fills and blocks them for good. The process is polled, so nothing waits on
  # it, and on timeout its whole tree is killed and the failure carries what it had printed.
  TIMEOUT = 180

  def capture(*command)
    dir = Dir.mktmpdir('adopted')
    begin
      out, err = %w[out err].map { File.join(dir, it) }
      pid = Bundler.with_unbundled_env do
        Process.spawn(env, *command, chdir: ROOT, in: File::NULL, out:, err:,
                                     **(Gem.win_platform? ? {} : { pgroup: true }))
      end
      deadline = Time.now + TIMEOUT
      nil
      sleep 0.1 until (status = Process.wait2(pid, Process::WNOHANG)&.last) || Time.now > deadline
      unless status
        kill_tree(pid)
        raise "#{command.first(3).join(' ')} did not finish in #{TIMEOUT}s. It printed:\n" \
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

  # Boots the app, evaluates `code` and returns its value, round-tripped through JSON, with the
  # process's stderr (the Rails log).
  def run(code)
    script = "require './config/environment'\n" \
             "result = begin\n#{code}\nend\n$stdout.write(JSON.generate(result))\n"
    out, err, status = capture(RbConfig.ruby, '-e', script)
    raise "the adopted app failed:\n#{err}" unless status.success?

    [JSON.parse(out), err]
  end

  # Runs the block with `path` (relative to the app) holding `body`, restoring it after.
  def with_file(path, body)
    full = File.join(ROOT, path)
    before = File.exist?(full) ? File.binread(full) : nil
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
    yield
  ensure
    before ? File.binwrite(full, before) : FileUtils.rm_f(full)
  end
end
