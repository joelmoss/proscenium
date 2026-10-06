# frozen_string_literal: true

require 'fileutils'
require_relative '../context_map'

module Proscenium
  module CLI
    # One install at a time per project, and a marker while one is under way (#154).
    #
    # The lock is `flock` on `.proscenium/lock`, so the operating system releases it when its
    # holder dies and there is nothing stale to reclaim. The marker,
    # `.proscenium/installing`, outlives an interrupted install: the engine refuses to build while
    # it exists, and the next install removes it once it has finished.
    #
    # The holder's name goes in `.proscenium/holder`, not in the lock file: Windows locks are
    # mandatory, so a second install could not read a locked file to say who holds it.
    #
    # The lock is not handed to the manager: every process the manager starts would inherit it, so
    # a daemon a lifecycle script left running would hold it. So a killed CLI releases the lock
    # while its manager runs on; the manager's pid goes in `.proscenium/manager` while it runs, and
    # an install that finds that process alive is refused as if the lock were held.
    class ProjectLock
      DIR = '.proscenium'

      NOFOLLOW = File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0

      # Writes one of install's own files, never through a link: a checkout could point one at any
      # file the user can write. The open refuses a link itself where the OS can (O_NOFOLLOW), so
      # one swapped in after the check is refused too.
      def self.write(path, text)
        raise Error.new('PSM-E-OWNED-LINK', paths: path) if File.symlink?(path)

        File.open(path, File::WRONLY | File::CREAT | File::TRUNC | NOFOLLOW, 0o644) { it.write(text) }
      rescue Errno::ELOOP, Errno::EMLINK
        raise Error.new('PSM-E-OWNED-LINK', paths: path)
      end

      def initialize(root)
        @root = root
        @dir = File.join(root, DIR)
      end

      # The engine probes these two to refuse builds during an install, so both sides share them.
      def lock_path = File.join(@root, ContextMap::LOCK)
      def marker_path = File.join(@root, ContextMap::INSTALLING)
      def holder_path = File.join(@dir, 'holder')
      def manager_path = File.join(@dir, 'manager')

      # Takes the lock for the block, or raises PSM-E-BUSY naming the install that holds it.
      def synchronize(command)
        FileUtils.mkdir_p(@dir)
        @io = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
        unless acquired? && !(manager = running_manager)
          holder = File.exist?(holder_path) ? File.read(holder_path).strip : ''
          holder = "the package manager (pid #{manager}) of a stopped #{holder}" if manager
          @io.close
          raise Error.new('PSM-E-BUSY', holder: holder.empty? ? 'another install' : holder)
        end

        self.class.write(holder_path, "#{command} (pid #{Process.pid})\n")
        yield self
      ensure
        @io&.close unless @io&.closed?
      end

      # The lock, retried for a second: a running Rails app probes it with a shared lock for a few
      # microseconds at a time, and that must not read as another install.
      def acquired?
        20.times do
          return true if @io.flock(File::LOCK_EX | File::LOCK_NB)

          sleep 0.05
        end
        false
      end

      # The pid of a manager an earlier install started that is still running, or nil.
      # ponytail: a reused pid reads as busy until that process exits; a process start time would
      # tell them apart.
      def running_manager
        return unless File.exist?(manager_path)

        pid = File.read(manager_path).to_i
        return unless pid.positive?

        Process.kill(0, pid)
        pid
      rescue Errno::ESRCH
        nil
      rescue Errno::EPERM
        pid
      end

      def manager_started(pid) = self.class.write(manager_path, "#{pid}\n")

      def manager_finished = FileUtils.rm_f(manager_path)

      # Whether an earlier install was interrupted before it finished.
      def interrupted? = File.exist?(marker_path)

      def mark! = self.class.write(marker_path, "#{Process.pid}\n")

      def unmark! = FileUtils.rm_f(marker_path)
    end
  end
end
