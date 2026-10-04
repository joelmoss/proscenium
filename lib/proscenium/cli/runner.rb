# frozen_string_literal: true

require 'bundler'

module Proscenium
  module CLI
    # Runs the package manager (#154): an argument array, never a shell, so no package name is ever
    # interpreted; in the project root; with the environment a direct native install would have,
    # not Bundler's (as the Rakefile does for `gem build`), so a dependency's lifecycle script that
    # runs Ruby sees the app's own setup. The project lock's descriptor is passed down, so the
    # manager holds the lock for as long as it runs.
    module Runner
      SIGNALS = %w[INT TERM].freeze

      module_function

      # Runs `executable` with `args` in `root` and returns when it exits. Options: `lock_io` (the
      # project lock to hand down), `on_spawn` (called with the manager's pid), `out` and `err`
      # (default: stderr, so stdout stays the CLI's summary), and `manager` (its name in errors).
      # Raises PSM-E-INTERRUPTED if a signal stopped it, PSM-E-NATIVE if it failed.
      # Its output is also kept, the last TAIL bytes of it, so a failure can say which gem it
      # involves; the error carries it as `output`.
      def run(executable, args, root:, **opts)
        reader, writer = IO.pipe
        spawn = { chdir: root, out: writer, err: writer, in: File::NULL }
        # Ruby on Windows cannot hand a child a descriptor ("wrong file descriptor"), so there the
        # CLI alone holds the lock (C53).
        spawn[opts[:lock_io]] = opts[:lock_io] if opts[:lock_io] && !Gem.win_platform?
        pid = Bundler.with_unbundled_env { Process.spawn(ENV.to_h, executable, *args, **spawn) }
        writer.close
        opts[:on_spawn]&.call(pid)
        output = relay(reader, opts.fetch(:out, $stderr))
        interrupted = []
        previous = forward_signals(pid, interrupted)
        _, status = Process.wait2(pid)
        check(status, opts.fetch(:manager) { File.basename(executable) }, args, output.value,
              interrupted.first)
      ensure
        previous&.each { |signal, handler| Signal.trap(signal, handler) }
        reader&.close unless reader&.closed?
      end

      TAIL = 64 * 1024

      # Copies the manager's output to `destination` as it arrives, keeping its tail.
      def relay(reader, destination)
        Thread.new do
          kept = +''
          loop do
            chunk = reader.readpartial(4096)
            destination.write(chunk)
            kept << chunk
            kept = kept.byteslice(-TAIL, TAIL) if kept.bytesize > TAIL
          end
        rescue IOError # EOFError included: the manager closed its output
          kept
        end
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

      # A manager that failed after the CLI was interrupted was interrupted too: on Windows it exits
      # with a status, not a signal.
      def check(status, manager, args, output, interrupted = nil)
        return status if status.success?

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
