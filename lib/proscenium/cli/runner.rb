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
      # project lock to hand down), `out` and `err` (default: stderr, so stdout stays the CLI's
      # summary), and `manager` (its name in errors). Raises PSM-E-INTERRUPTED if a signal stopped
      # it, PSM-E-NATIVE if it failed.
      def run(executable, args, root:, **opts)
        spawn = { chdir: root, out: opts.fetch(:out, $stderr), err: opts.fetch(:err, $stderr),
                  in: :close }
        spawn[opts[:lock_io]] = opts[:lock_io] if opts[:lock_io]
        pid = Bundler.with_unbundled_env { Process.spawn(ENV.to_h, executable, *args, **spawn) }
        previous = forward_signals(pid)
        _, status = Process.wait2(pid)
        check(status, opts.fetch(:manager) { File.basename(executable) }, args)
      ensure
        previous&.each { |signal, handler| Signal.trap(signal, handler) }
      end

      # INT and TERM reach the child, and the CLI waits for it rather than leaving it orphaned.
      def forward_signals(pid)
        SIGNALS.to_h do |signal|
          handler = Signal.trap(signal) do
            Process.kill(signal, pid)
          rescue Errno::ESRCH
            nil
          end
          [signal, handler]
        end
      end

      def check(status, manager, args)
        return status if status.success?

        command = [manager, *args].join(' ')
        if status.signaled?
          raise Error.new('PSM-E-INTERRUPTED', command:, details: { signal: status.termsig })
        end

        raise Error.new('PSM-E-NATIVE', command:, status: status.exitstatus,
                                        details: { exitStatus: status.exitstatus })
      end
    end
  end
end
