# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'proscenium/cli/project_lock'
require 'proscenium/cli/runner'

# The project lock and install marker, and running the manager (#154, C34, C35).
describe 'project lock and runner' do
  Lock = Proscenium::CLI::ProjectLock
  Runner = Proscenium::CLI::Runner

  before { @root = Dir.mktmpdir('lock') }
  after { FileUtils.rm_rf(@root) }

  def ruby(code) = [RbConfig.ruby, ['-e', code]]

  it 'lets one install at a time hold the lock, and names the holder' do
    Lock.new(@root).synchronize('proscenium install') do
      error = assert_raises(Proscenium::CLI::Error) { Lock.new(@root).synchronize('second') { flunk } }

      assert_equal ['PSM-E-BUSY', 7], [error.code, error.exit_status]
      assert_includes error.message, "proscenium install (pid #{Process.pid})"
    end
    Lock.new(@root).synchronize('again') { pass }
  end

  it 'leaves the install marker until it is removed' do
    lock = Lock.new(@root)
    lock.synchronize('install') { lock.mark! }

    assert_predicate Lock.new(@root), :interrupted?
    lock.unmark!

    refute_predicate Lock.new(@root), :interrupted?
  end

  it 'runs the manager in the project root, outside Bundler' do
    out = File.join(@root, 'out')
    exe, args = ruby("File.write(#{out.inspect}, [Dir.pwd, ENV['BUNDLE_GEMFILE'].to_s].join('|'))")
    Runner.run(exe, args, root: @root)

    dir, gemfile = File.read(out).split('|', -1)

    assert_equal File.realpath(@root), File.realpath(dir)
    assert_empty gemfile
  end

  it 'maps a failure to exit 6 with the native status, and a signal to exit 8' do
    exe, args = ruby('exit 3')
    error = assert_raises(Proscenium::CLI::Error) { Runner.run(exe, args, root: @root, manager: 'pnpm') }

    assert_equal ['PSM-E-NATIVE', 6, { exitStatus: 3 }],
                 [error.code, error.exit_status, error.details]
    skip 'signals are POSIX' if Gem.win_platform?

    exe, args = ruby('Process.kill(:TERM, Process.pid); sleep 1')
    error = assert_raises(Proscenium::CLI::Error) { Runner.run(exe, args, root: @root) }

    assert_equal ['PSM-E-INTERRUPTED', 8], [error.code, error.exit_status]
  end

  # A manager that outlives the CLI keeps the project locked (C35): it was handed the lock.
  it 'passes the lock to the manager, which holds it while it runs' do
    skip 'descriptor inheritance is qualified on Windows separately' if Gem.win_platform?

    pid = File.join(@root, 'pid')
    manager = nil
    Lock.new(@root).synchronize('install') do |lock|
      exe, args = ruby("File.write(#{pid.inspect}, Process.pid.to_s); sleep 5")
      manager = Thread.new do
        Runner.run(exe, args, root: @root, lock_io: lock.io)
      rescue Proscenium::CLI::Error => e
        e
      end
      sleep 0.05 until File.exist?(pid) && !File.read(pid).empty?
    end

    # The CLI's own descriptor is closed: only the running manager holds the lock now.
    assert_raises(Proscenium::CLI::Error) { Lock.new(@root).synchronize('retry') { flunk } }
    Process.kill(:KILL, File.read(pid).to_i)

    assert_equal 'PSM-E-INTERRUPTED', manager.value.code
    Lock.new(@root).synchronize('after') { pass }
  end
end
