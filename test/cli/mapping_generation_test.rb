# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'proscenium/mapping_generation'

# Mapping generations (#154): a change to a file the context map is built from starts a new one,
# at most once a second, and nothing read in an older one leaks into it.
describe Proscenium::MappingGeneration do
  MG = Proscenium::MappingGeneration

  before do
    @root = Dir.mktmpdir('generation')
    package('pnpm-link' => 'link:vendor/pnpm-link')
    MG.reset!
    MG.refresh(@root, every: 0)
  end

  after { FileUtils.rm_rf(@root) }

  def package(dependencies)
    File.write(File.join(@root, 'package.json'), JSON.generate('dependencies' => dependencies))
  end

  # A later mtime than the last write, without sleeping a whole filesystem tick.
  def touch(path, offset)
    File.utime(Time.now + offset, Time.now + offset, File.join(@root, path))
  end

  def local_packages(generation)
    Proscenium::ContextMap.config(@root, generation)[:AppLocalPackages]
  end

  it 'keeps the generation while nothing changes' do
    number, = MG.refresh(@root, every: 0)

    assert_equal [number, false], MG.refresh(@root, every: 0)
  end

  it 'starts a new generation, with a fresh map, when a watched file changes' do
    before, = MG.refresh(@root, every: 0)

    assert_equal ['pnpm-link'], local_packages(before)

    package('pnpm-link' => 'link:vendor/pnpm-link', 'mine' => 'file:vendor/mine')
    touch('package.json', 5)
    after, changed = MG.refresh(@root, every: 0)

    assert changed
    assert_equal before + 1, after
    assert_equal %w[mine pnpm-link], local_packages(after)
  end

  it 'starts one when an install finishes and its marker goes' do
    FileUtils.mkdir_p(File.join(@root, '.proscenium'))
    File.write(File.join(@root, '.proscenium/installing'), '1')

    assert MG.refresh(@root, every: 0).last
    File.delete(File.join(@root, '.proscenium/installing'))

    assert MG.refresh(@root, every: 0).last
  end

  # The Railtie takes the first look at boot, so a change made after boot, such as running
  # `proscenium install` while the server runs, starts a new generation at the next build.
  it 'sees a change made after the first look' do
    MG.reset!
    MG.refresh(@root) # at boot
    touch('package.json', 5)

    assert MG.refresh(@root, every: 0).last
  end

  it 'looks at most once per interval' do
    touch('package.json', 5)

    refute MG.refresh(@root, every: 60).last
  end

  # Puma serves requests on many threads; each asks for the generation and its map while a
  # watched file keeps changing.
  it 'gives concurrent callers a consistent map while files change' do
    errors = Queue.new
    stop = false
    writer = Thread.new do
      10.times do |i|
        touch('package.json', i + 1)
        sleep 0.002
      end
      stop = true
    end
    readers = Array.new(8) do
      Thread.new do
        until stop
          number, = MG.refresh(@root, every: 0)
          errors << local_packages(number) unless local_packages(number) == ['pnpm-link']
        end
      rescue StandardError => e
        errors << e
      end
    end
    [writer, *readers].each(&:join)

    assert_empty errors
  end
end
