# frozen_string_literal: true

require 'fileutils'

module Proscenium
  module CLI
    # One install at a time per project, and a marker while one is under way (#154).
    #
    # The lock is `flock` on `.proscenium/lock`, so the operating system releases it when its
    # holder dies and there is nothing stale to reclaim. Its descriptor is handed to the package
    # manager, so a manager that outlives a killed CLI still holds it. The marker,
    # `.proscenium/installing`, outlives an interrupted install: the engine refuses to build while
    # it exists, and the next install removes it once it has finished.
    class ProjectLock
      DIR = '.proscenium'

      attr_reader :io

      def initialize(root)
        @dir = File.join(root, DIR)
      end

      def lock_path = File.join(@dir, 'lock')
      def marker_path = File.join(@dir, 'installing')

      # Takes the lock for the block, or raises PSM-E-BUSY naming the install that holds it.
      def synchronize(command)
        FileUtils.mkdir_p(@dir)
        @io = File.open(lock_path, File::RDWR | File::CREAT, 0o644)
        unless @io.flock(File::LOCK_EX | File::LOCK_NB)
          holder = File.read(lock_path).strip
          @io.close
          raise Error.new('PSM-E-BUSY', holder: holder.empty? ? 'another install' : holder)
        end

        @io.truncate(0)
        @io.write("#{command} (pid #{Process.pid})\n")
        @io.flush
        yield self
      ensure
        @io&.close unless @io&.closed?
      end

      # Whether an earlier install was interrupted before it finished.
      def interrupted? = File.exist?(marker_path)

      def mark! = File.write(marker_path, "#{Process.pid}\n")

      def unmark! = FileUtils.rm_f(marker_path)
    end
  end
end
