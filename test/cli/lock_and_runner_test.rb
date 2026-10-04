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

  # A running Rails app probes the lock with a shared lock (ContextMap.installing?). That must
  # not read as another install.
  it 'waits out a probe of the lock rather than reporting busy' do
    FileUtils.mkdir_p(File.join(@root, '.proscenium'))
    held = Queue.new
    probe = Thread.new do
      File.open(File.join(@root, '.proscenium/lock'), File::RDONLY | File::CREAT) do |io|
        io.flock(File::LOCK_SH)
        held << true
        sleep 0.2
      end
    end
    held.pop

    Lock.new(@root).synchronize('install') { pass }
    probe.join
  end

  # On Windows a killed install releases the lock while its manager runs on, so the manager's pid
  # is recorded too, and an install that finds it alive is busy (C35, C53).
  it 'is busy while a manager a stopped install started is still running' do
    manager = Process.spawn(RbConfig.ruby, '-e', 'sleep 30')
    lock = Lock.new(@root)
    lock.synchronize('install') { lock.manager_started(manager) }

    busy = assert_raises(Proscenium::CLI::Error) { Lock.new(@root).synchronize('retry') { flunk } }

    assert_equal 'PSM-E-BUSY', busy.code
    assert_includes busy.message, "the package manager (pid #{manager})"

    Process.kill(:KILL, manager)
    Process.wait(manager)
    manager = nil
    Lock.new(@root).synchronize('after') { pass }
  ensure
    if manager
      Process.kill(:KILL, manager)
      Process.wait(manager)
    end
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
      sleep 0.05 until File.exist?(pid) && !File.empty?(pid)
    end

    # The CLI's own descriptor is closed: only the running manager holds the lock now.
    assert_raises(Proscenium::CLI::Error) { Lock.new(@root).synchronize('retry') { flunk } }
    Process.kill(:KILL, File.read(pid).to_i)

    assert_equal 'PSM-E-INTERRUPTED', manager.value.code
    Lock.new(@root).synchronize('after') { pass }
  end

  # C53 on Windows, qualified on windows-latest rather than assumed from POSIX behaviour.
  describe 'on Windows' do
    before { skip 'Windows only' unless Gem.win_platform? }

    LIB = File.expand_path('../../lib', __dir__)

    # An install as the CLI runs one: it takes the project lock and runs a manager that records
    # its pid in `started`, then sleeps. A Proscenium error becomes its exit status.
    HARNESS = <<~RUBY
      require 'rbconfig'
      require 'proscenium/cli/error'
      require 'proscenium/cli/project_lock'
      require 'proscenium/cli/runner'
      root, started = ARGV
      begin
        Proscenium::CLI::ProjectLock.new(root).synchronize('harness') do |lock|
          code = "File.write(\#{started.dump}, Process.pid.to_s); sleep 30"
          Proscenium::CLI::Runner.run(RbConfig.ruby, ['-e', code], root:, lock_io: lock.io,
                                      on_spawn: lock.method(:manager_started))
        ensure
          lock&.manager_finished
        end
      rescue Proscenium::CLI::Error => e
        warn e.code
        exit e.exit_status
      end
    RUBY

    def install(**)
      @started = File.join(@root, 'started')
      @log = File.join(@root, 'harness.log')
      pid = Process.spawn(RbConfig.ruby, '-I', LIB, '-e', HARNESS, @root, @started, err: @log, **)
      deadline = Time.now + 30
      sleep 0.05 until (File.exist?(@started) && !File.empty?(@started)) || Time.now > deadline
      [pid, File.read(@started).to_i]
    end

    def alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def exited?(pid, seconds = 10)
      deadline = Time.now + seconds
      sleep 0.05 while alive?(pid) && Time.now < deadline
      !alive?(pid)
    end

    # pnpm and Bun are `.cmd` shims, which cmd.exe runs, re-parsing every argument.
    it 'passes the arguments install builds through a .cmd shim intact' do
      shim = File.join(@root, 'manager.cmd')
      # The runner gives the manager the environment from before Bundler, so the shim names Ruby
      # itself rather than reading it from a variable the test sets.
      File.write(shim, "@echo off\r\n\"#{RbConfig.ruby.tr('/', '\\')}\" -e " \
                       "\"File.write(ARGV.shift, ARGV.join(10.chr))\" \"%~dp0args.txt\" %*\r\n")
      args = ['install', '--frozen-lockfile', '--prod', '--offline',
              '--filter=!@rubygems/gem_npm', '--store-dir=C:\\a b\\store']

      Runner.run(shim, args, root: @root)

      assert_equal args, File.read(File.join(@root, 'args.txt')).split("\n")
    end

    # A console's Ctrl-C reaches every process attached to it. CTRL_BREAK to the install's own
    # process group is the nearest a test can send: Windows ignores CTRL_C in a new group.
    it 'stops the manager on Ctrl-C and reports the install interrupted (exit 8)' do
      require 'fiddle'
      kernel32 = Fiddle.dlopen('kernel32')
      generate = Fiddle::Function.new(kernel32['GenerateConsoleCtrlEvent'],
                                      [Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      pid, manager = install(new_pgroup: true)

      refute_equal 0, generate.call(1, pid), "GenerateConsoleCtrlEvent: #{Fiddle.win32_last_error}"
      _, status = Process.wait2(pid)

      assert_equal 8, status.exitstatus, File.read(@log)
      assert exited?(manager), 'the manager outlived the interrupted install'
    end

    # C35: a manager that outlives a killed install keeps the project locked until it exits.
    it 'keeps the lock while a manager outlives a killed install' do
      pid, manager = install
      Process.kill(:KILL, pid)
      Process.wait(pid)

      busy = assert_raises(Proscenium::CLI::Error) { Lock.new(@root).synchronize('retry') { flunk } }

      assert_equal 'PSM-E-BUSY', busy.code
    ensure
      Process.kill(:KILL, manager) if manager && alive?(manager)
      exited?(manager) if manager
      Lock.new(@root).synchronize('after') { pass } if manager
    end
  end
end
