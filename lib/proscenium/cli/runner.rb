# frozen_string_literal: true

require 'bundler'

module Proscenium
  module CLI
    # Runs the package manager (#154): an argument array, never a shell, so no package name is ever
    # interpreted; in the project root; with the environment a direct native install would have,
    # not Bundler's (as the Rakefile does for `gem build`), so a dependency's lifecycle script that
    # runs Ruby sees the app's own setup. The project lock is not passed down: every process the
    # manager starts would inherit it, so a daemon a lifecycle script left behind would hold it.
    # The manager's pid record keeps a manager that outlives a killed CLI from being joined.
    module Runner
      SIGNALS = %w[INT TERM].freeze

      module_function

      # Runs `executable` with `args` in `root` and returns when it exits. Options: `on_spawn`
      # (called with the manager's pid), `out` (default: stderr, so stdout stays the CLI's
      # summary), and `manager` (its name in errors).
      # Raises PSM-E-INTERRUPTED if a signal stopped it, PSM-E-NATIVE if it failed.
      # Its output is also kept, the last TAIL bytes of it, so a failure can say which gem it
      # involves; the error carries it as `output`.
      def run(executable, args, root:, **opts)
        reader, writer = IO.pipe
        spawn = { chdir: root, out: writer, err: writer, in: File::NULL }
        pid = Bundler.with_unbundled_env { Process.spawn(ENV.to_h, executable, *args, **spawn) }
        writer.close
        record(pid, opts[:on_spawn])
        kept = +''
        relaying = relay(reader, opts.fetch(:out, $stderr), kept)
        interrupted = []
        previous = forward_signals(pid, interrupted)
        _, status = Process.wait2(pid)
        await_interrupt(status, interrupted)
        # A process the manager left running may hold its output open: once the manager has
        # exited, its output gets a moment to drain, and no more.
        relaying.kill unless relaying.join(DRAIN)
        check(status, opts.fetch(:manager) { File.basename(executable) }, args, kept.dup,
              interrupted.first)
      ensure
        previous&.each { |signal, handler| Signal.trap(signal, handler) }
        reader&.close unless reader&.closed?
      end

      # Hands the manager's pid to `on_spawn`, which records it. A manager whose pid was not
      # recorded is stopped: the install is failing and releasing its lock, and a manager left
      # running unrecorded would run beside the next install.
      def record(pid, on_spawn)
        recorded = false
        on_spawn&.call(pid)
        recorded = true
      ensure
        unless recorded
          begin
            Process.kill(:KILL, pid)
          rescue Errno::ESRCH
            nil
          end
          Process.wait(pid)
        end
      end

      TAIL = 64 * 1024
      # Seconds the manager's output may keep draining after it exits.
      DRAIN = 1

      # Copies the manager's output to `destination` as it arrives, keeping its tail. A destination
      # that fails, such as a closed `| head`, is dropped but the pipe is still drained: a manager
      # left blocked on a full pipe would never exit, and the lock would stay held.
      def relay(reader, destination, kept)
        Thread.new do
          loop do
            chunk = reader.readpartial(4096)
            destination = write(destination, chunk)
            kept << chunk
            kept.replace(kept.byteslice(-TAIL, TAIL)) if kept.bytesize > TAIL
          end
        rescue IOError # EOFError included: the manager closed its output
          nil
        end
      end

      # Writes `chunk` to `destination`, returning it, or nil once it has failed.
      def write(destination, chunk)
        destination&.write(chunk)
        destination
      rescue IOError, SystemCallError
        nil
      end

      # INT and TERM reach the child, and the CLI waits for it rather than leaving it orphaned. On
      # Windows the console already delivers Ctrl-C to the manager, and Process.kill cannot send
      # it, so there the CLI only notes the interruption and waits. Ctrl-Break ends the CLI
      # outright: Ruby has no SIGBREAK to trap. The marker and the manager's pid record then
      # keep the next install and the engine safe, as after any killed install.
      def forward_signals(pid, interrupted)
        SIGNALS.to_h do |signal|
          handler = Signal.trap(signal) do
            interrupted << signal
            Process.kill(signal, pid) unless Gem.win_platform?
          rescue Errno::ESRCH
            nil
          end
          [signal, handler]
        end
      end

      # Seconds a failed manager waits, on Windows, for the CLI's Ctrl-C handler.
      GRACE = 0.5

      # On Windows Ctrl-C reaches the manager and the CLI alike, and the manager can exit before the
      # CLI's handler has run, so a failed manager waits a moment for it: an interrupted install is
      # then reported as one, not as a failed manager. A sleep lets a pending handler run.
      def await_interrupt(status, interrupted)
        return if status.success? || !interrupted.empty? || !Gem.win_platform?

        deadline = now + GRACE
        sleep 0.01 while interrupted.empty? && now < deadline
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # An interrupted install stops, however the manager ended: on Windows it exits with a status,
      # not a signal, and may even exit 0, and Ctrl-C still means stop before verifying anything.
      def check(status, manager, args, output, interrupted = nil)
        return status if status.success? && !interrupted

        command = [manager, *args].join(' ')
        error = if status.signaled? || interrupted
                  Error.new('PSM-E-INTERRUPTED', command:,
                                                 details: { signal: status.termsig || interrupted })
                else
                  Error.new('PSM-E-NATIVE', command:, status: status.exitstatus,
                                            details: { exitStatus: status.exitstatus })
                end
        error.output = output
        raise error
      end
    end
  end
end
