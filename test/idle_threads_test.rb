# frozen_string_literal: true

require 'test_helper'
require 'open3'

# Go never ends a thread by itself, so a Puma worker that had used the library kept about
# GOMAXPROCS idle threads for life, and enough workers exhausted a container's task limit (#182).
# Run in a subprocess, as the threads in this one depend on what the suite happened to run first.
class Proscenium::IdleThreadsTest < ActiveSupport::TestCase
  ROOT = Pathname.new(__dir__).join('..').expand_path

  SCRIPT = <<~'RUBY'
    require 'json'
    require 'proscenium/builder'

    request = Proscenium::Builder::Request
    config = FFI::MemoryPointer.from_string(
      { RootPath: File.expand_path('fixtures/dummy'), OutputDir: 'public/assets', Environment: 3,
        Bundle: true }.to_json
    )
    build = lambda do
      result = request.build_to_string('lib/foo.js', config)
      abort result[:response].read_string unless result[:success]
    end
    threads = lambda do
      if File.directory?('/proc/self/task')
        Dir['/proc/self/task/*'].size
      else
        `ps -M -p #{Process.pid}`.lines.size - 1
      end
    end

    5.times { build.call }
    busy = threads.call

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    sleep 0.25 while threads.call >= busy - 4 &&
                     Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    idle = threads.call

    build.call
    print "#{busy} #{idle}"
  RUBY

  it 'ends idle Go threads, and still builds afterwards' do
    skip 'counts threads with /proc or ps' if Gem.win_platform?

    out, err, status = Open3.capture3({ 'GOMAXPROCS' => '32' }, RbConfig.ruby, '-I', 'lib',
                                      '-e', SCRIPT, chdir: ROOT.to_s)

    assert_predicate status, :success?, err

    busy, idle = out.split.map(&:to_i)

    assert_operator idle, :<=, busy - 5, "#{busy} threads while busy, #{idle} once idle"
  end
end
