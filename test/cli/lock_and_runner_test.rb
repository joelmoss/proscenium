# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'proscenium/cli/project_lock'
require 'proscenium/cli/runner'
require 'proscenium/context_map'

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

  # On Windows Ctrl-C reaches the manager and the CLI alike, and the manager can exit before the
  # CLI's handler has run: a failed manager waits a moment for it, so an interrupted install is not
  # reported as a failed one. Elsewhere, and for a manager that succeeded, nothing waits.
  it 'waits briefly for a Ctrl-C handler when a manager fails on Windows' do
    failed = Struct.new(:success?).new(false)
    interrupted = []
    windows = Gem.method(:win_platform?)
    Gem.define_singleton_method(:win_platform?) { true }
    Thread.new { sleep 0.05 and interrupted << 'INT' }
    Runner.await_interrupt(failed, interrupted)

    assert_equal ['INT'], interrupted
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Runner.await_interrupt(failed, [])

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :>=, Runner::GRACE
    Gem.define_singleton_method(:win_platform?) { false }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Runner.await_interrupt(failed, [])

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.05
  ensure
    Gem.define_singleton_method(:win_platform?, windows)
  end

  # Install's own files under .proscenium/ are never written through a link, which a hostile
  # checkout could point at any file the user can write.
  it 'refuses to write its holder or marker through a link' do
    skip 'symlinks need privileges here' if Gem.win_platform?

    victim = File.join(@root, 'victim')
    File.write(victim, 'precious')
    FileUtils.mkdir_p(File.join(@root, '.proscenium'))
    %w[holder installing].each do |name|
      link = File.join(@root, '.proscenium', name)
      File.symlink(victim, link)
      error = assert_raises(Proscenium::CLI::Error) do
        Lock.new(@root).synchronize('proscenium install', &:mark!)
      end

      assert_equal 'PSM-E-OWNED-LINK', error.code
      assert_equal 'precious', File.read(victim)
      File.delete(link)
    end
  end

  # A link swapped in after the check is refused by the open itself, and the manager's pid record
  # is written the same way.
  it 'refuses a link the check did not see, and a linked manager record' do
    skip 'symlinks need privileges here' if Gem.win_platform?

    victim = File.join(@root, 'victim')
    File.write(victim, 'precious')
    FileUtils.mkdir_p(File.join(@root, '.proscenium'))
    link = File.join(@root, '.proscenium', 'manager')
    File.symlink(victim, link)
    lock = Lock.new(@root)
    symlink = File.method(:symlink?)
    File.define_singleton_method(:symlink?) { |_| false }
    begin
      assert_equal('PSM-E-OWNED-LINK', code { lock.manager_started(1) })
    ensure
      File.define_singleton_method(:symlink?, symlink)
    end

    assert_equal('PSM-E-OWNED-LINK', code { lock.manager_started(1) })
    assert_equal 'precious', File.read(victim)
  end

  def code(&) = assert_raises(Proscenium::CLI::Error, &).code

  # A closed output, as `proscenium install 2>&1 | head` leaves, must not stop the pipe being
  # drained: a manager blocked on a full pipe never exits, and the lock stays held.
  it 'keeps draining the manager after its output destination fails' do
    closed = Object.new
    def closed.write(*) = raise(Errno::EPIPE)
    exe, args = ruby('$stderr.write("x" * 300_000); exit 0')
    finished = Thread.new { Runner.run(exe, args, root: @root, out: closed) }

    assert finished.join(30), 'the manager blocked on a pipe nobody drained'
    assert_predicate finished.value, :success?
  end

  # Ctrl-C means stop, even when the manager catches it and exits 0, as one did on Windows.
  it 'reports an interrupted install even when the manager exits 0 (exit 8)' do
    skip 'Windows presses a real Ctrl-C in its own test below' if Gem.win_platform?

    ready = File.join(@root, 'ready')
    exe, args = ruby("trap(:INT) { exit 0 }; File.write(#{ready.inspect}, '1'); sleep 10")
    sender = Thread.new do
      sleep 0.05 until File.exist?(ready)
      Process.kill(:INT, Process.pid)
    end
    error = assert_raises(Proscenium::CLI::Error) { Runner.run(exe, args, root: @root) }
    sender.join

    assert_equal ['PSM-E-INTERRUPTED', 8], [error.code, error.exit_status]
  end

  # A background process a dependency's install script leaves running is not the install: it
  # must hold neither the lock nor the CLI. A manager that outlives a killed install keeps the
  # project busy through its pid record instead (C35, the test above).
  it 'lets an install end while a process the manager started lives on' do
    child = File.join(@root, 'child')
    script = "pid = Process.spawn(#{RbConfig.ruby.inspect}, '-e', 'sleep 6'); " \
             "File.write(#{child.inspect}, pid.to_s); Process.detach(pid)"
    exe, args = ruby(script)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Lock.new(@root).synchronize('install') do |lock|
      Runner.run(exe, args, root: @root, on_spawn: lock.method(:manager_started))
      lock.manager_finished
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 4, 'the CLI waited for the background process'
    Lock.new(@root).synchronize('retry') { pass }

    refute Proscenium::ContextMap.installing?(@root)
  ensure
    kill(File.read(child).to_i) if child && File.exist?(child)
  end

  # A manager whose pid cannot be recorded must not run on unrecorded once the install fails:
  # the lock is released, and the next install would run beside it.
  # It writes a heartbeat until stopped: a pid alone proves nothing on Windows, which can hand an
  # exited process's pid to another one straight away.
  it 'stops the manager when its pid cannot be recorded' do
    beat = File.join(@root, 'beat')
    exe, args = ruby("loop { File.write(#{beat.dump}, " \
                     'Process.clock_gettime(Process::CLOCK_MONOTONIC).to_s); sleep 0.02 }')
    pid = nil
    record = lambda do |spawned|
      pid = spawned
      sleep 0.01 until File.exist?(beat)
      raise Errno::ENOSPC
    end

    assert_raises(Errno::ENOSPC) { Runner.run(exe, args, root: @root, on_spawn: record) }
    stopped = File.read(beat)
    sleep 0.3

    assert_equal stopped, File.read(beat), 'the manager is still running'
  ensure
    kill(pid) if pid
  end

  def kill(pid)
    Process.kill(:KILL, pid) if pid.positive?
  rescue Errno::ESRCH
    nil
  end

  describe 'on Windows' do
    before { skip 'Windows only' unless Gem.win_platform? }

    HARNESS_LIB = File.expand_path('../../lib', __dir__)

    # The console calls the harness and the Ctrl-C helper make, through ffi, which Proscenium
    # already depends on: fiddle stopped being a default gem in Ruby 4.0, so a bundle cannot load
    # it there.
    KERNEL32 = <<~RUBY
      require 'ffi'
      module Kernel32
        extend FFI::Library
        ffi_lib 'kernel32'
        ffi_convention :stdcall
        attach_function :FreeConsole, [], :int
        attach_function :AttachConsole, [:uint], :int
        attach_function :SetConsoleCtrlHandler, %i[pointer int], :int
        attach_function :GenerateConsoleCtrlEvent, %i[uint uint], :int
      end
    RUBY

    # An install as the CLI runs one: it takes the project lock and runs a manager that records
    # its pid in `started`, then sleeps. It writes its own pid to `harness_pid`, and its exit
    # status, which a Proscenium error decides, to `result` when given one.
    HARNESS = <<~RUBY.freeze
      require 'rbconfig'
      require 'proscenium/cli/error'
      require 'proscenium/cli/project_lock'
      require 'proscenium/cli/runner'
      root, started, result = ARGV
      File.write(File.join(root, 'harness_pid'), Process.pid.to_s)
      if result # Ctrl-C on, as in an interactive console; a CI runner starts with it ignored
        #{KERNEL32}
        Kernel32.SetConsoleCtrlHandler(nil, 0)
      end
      status = begin
        Proscenium::CLI::ProjectLock.new(root).synchronize('harness') do |lock|
          code = "File.write(\#{started.dump}, Process.pid.to_s); sleep 90"
          Proscenium::CLI::Runner.run(RbConfig.ruby, ['-e', code], root:,
                                      on_spawn: lock.method(:manager_started))
        ensure
          lock&.manager_finished
        end
        0
      rescue Proscenium::CLI::Error => e
        warn e.code
        e.exit_status
      end
      File.write(result, status.to_s) if result
      exit status
    RUBY

    # Sends Ctrl-C to every process on the console of the process ARGV[0], as pressing it there
    # does: it attaches to that console, ignores the event itself, and generates CTRL_C_EVENT.
    CTRL_C = <<~RUBY.freeze
      #{KERNEL32}
      Kernel32.FreeConsole
      abort "AttachConsole: \#{FFI::LastError.winapi_error}" if Kernel32.AttachConsole(ARGV[0].to_i).zero?
      Kernel32.SetConsoleCtrlHandler(nil, 1)
      abort "GenerateConsoleCtrlEvent: \#{FFI::LastError.winapi_error}" if Kernel32.GenerateConsoleCtrlEvent(0, 0).zero?
    RUBY

    def install(**)
      @started = File.join(@root, 'started')
      @log = File.join(@root, 'harness.log')
      pid = Process.spawn(RbConfig.ruby, '-I', HARNESS_LIB, '-e', HARNESS, @root, @started,
                          err: @log, **)
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

    # Ctrl-C reaches every process on the console, the CLI and its manager alike, so the install
    # runs in a console of its own (`start`), and the test presses Ctrl-C there. Ctrl-Break is no
    # stand-in: Ruby has no SIGBREAK, so it ends the CLI before any trap runs.
    it 'stops the manager on Ctrl-C and reports the install interrupted (exit 8)' do
      started = File.join(@root, 'started')
      result = File.join(@root, 'result')
      File.write(File.join(@root, 'harness.rb'), HARNESS)
      args = [RbConfig.ruby, '-I', HARNESS_LIB, File.join(@root, 'harness.rb'), @root, started,
              result]
      File.write(File.join(@root, 'launch.cmd'),
                 "start \"\" /min #{args.map { "\"#{it.tr('/', '\\')}\"" }.join(' ')}\r\n")
      system(File.join(@root, 'launch.cmd'), exception: true)
      deadline = Time.now + 30
      sleep 0.05 until (File.exist?(started) && !File.empty?(started)) || Time.now > deadline
      harness = File.read(File.join(@root, 'harness_pid')).to_i
      manager = File.read(started).to_i

      system(RbConfig.ruby, '-e', CTRL_C, harness.to_s, exception: true)

      # The manager sleeps for 90 seconds, so stopping within 30 means Ctrl-C stopped it.
      assert exited?(manager, 30), 'Ctrl-C did not stop the manager'
      # File.write creates the file before it writes, so an empty one is not the report yet.
      deadline = Time.now + 30
      sleep 0.05 until (File.exist?(result) && !File.empty?(result)) || Time.now > deadline

      assert_equal '8', File.exist?(result) && File.read(result), 'the install did not report'
    ensure
      [harness, manager].each { Process.kill(:KILL, it) if it && alive?(it) }
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
