# frozen_string_literal: true

require 'bundler/setup'
require 'bundler/gem_tasks'
require 'json'
require 'open3'

CLOBBER.include 'pkg'

# See https://github.com/techknowlogick/xgo

task default: %i[test rubocop]
task release: %i[build push]

#
# Go target      | Ruby gem platform  | built by
# ---------------|--------------------|----------------------------------
# darwin/arm64   | arm64-darwin       | native, CGO_ENABLED=1
# darwin/amd64   | x86_64-darwin      | native, CGO_ENABLED=1
# linux/arm64    | aarch64-linux-gnu  | xgo
# linux/amd64    | x86_64-linux-gnu   | xgo
# windows/amd64  | x64-mingw-ucrt     | native, CGO_ENABLED=1, on a Windows host
#
# Windows builds natively because xgo cannot: its mingw-w64 linker rejects the export definition
# Go generates for c-shared (`export_file.def:1: syntax error`). The library is a `.dll`, named
# explicitly - see LIBRARY_NAME in lib/proscenium/builder.rb.
#
# The Linux gems name their libc. A BARE `x86_64-linux` matches glibc and musl alike, so an
# Alpine host installed it and got a glibc shared library it could not load, with a dlopen
# failure naming a path and nothing to say the platform was the problem. `-gnu` is never
# selected on musl, so after this rename an Alpine host matches no platform gem at all: it gets
# the platform-less gem and Proscenium::Builder::UnsupportedPlatform, which says so.
#
# There are deliberately NO musl gems. Go's c-shared libraries cannot be dlopen'd on musl -
# they carry initial-exec TLS relocations that musl refuses by design - and Ruby's FFI loads
# this library with dlopen. The build succeeds and produces a correctly musl-linked library;
# it simply cannot be loaded, failing with:
#
#   Error relocating ...: free: initial-exec TLS resolves to dynamic definition
#
# That is golang/go#54805, open since 2022. The linker flag that would fix it is in neither
# Go 1.25 nor Go 1.27. Revisit when it ships; nothing else here needs to change.
#
# Consequence for existing users: `x86_64-linux` is no longer a platform Proscenium publishes,
# so a lockfile pinned to it wants `bundle lock --add-platform x86_64-linux-gnu`. The Linux gems
# declare required_rubygems_version >= 3.3.22 (see the gemspec) so an older RubyGems, which
# cannot tell the variants apart, refuses them instead of installing the wrong one.

# Ruby => Go
PLATFORMS = {
  'x86_64-darwin' => 'darwin/amd64',
  'arm64-darwin' => 'darwin/arm64',
  'aarch64-linux-gnu' => 'linux/arm64',
  'x86_64-linux-gnu' => 'linux/amd64',
  'x64-mingw-ucrt' => 'windows/amd64'
}.freeze

# Built by the Go toolchain on a host of the same OS. Everything else goes through xgo.
NATIVE_GOOS = %w[darwin windows].freeze

# The compiled library's file name for a Go OS. Must match LIBRARY_NAME in
# lib/proscenium/builder.rb, which is what loads it.
library_name = ->(goos) { goos == 'windows' ? 'proscenium.dll' : 'proscenium' }

base = FileUtils.pwd
pkg_dir = File.join(base, 'pkg')
ext_dir = 'lib/proscenium/ext'
ext_path = Pathname.new(base).join(ext_dir)
built_path = ext_path.join('joelmoss')
gemspec = Bundler.load_gemspec('proscenium.gemspec')

# Pushing has to be resumable. A release publishes one gem per platform, and a run that dies
# partway leaves some of them up: re-running it then failed on every gem that had already gone,
# so the version stayed half-published and the platforms that missed out resolved to an older
# release instead. Nothing warned about it.
#
# RubyGems answers a duplicate push with "has already been pushed", which is the outcome we want
# - the artifact is where it should be - so treat it as success and carry on to the next gem.
# Checked from the push's own output rather than by asking the API first, so a network blip
# cannot make us skip a gem that was never published.
push_gem = lambda do |gem_file|
  out, status = Open3.capture2e('gem', 'push', gem_file)
  puts out

  return if status.success?
  raise "gem push failed for #{gem_file}" unless out.include?('has already been pushed')

  puts "---> Already published, skipping #{File.basename(gem_file)}"
end

desc 'Print the platform list as JSON, for the release workflow matrix'
task 'platforms:json' do
  puts PLATFORMS.keys.to_json
end

desc 'Compile for local os/arch'
task 'compile:local' => 'clobber:ext' do
  sh 'go', 'build', '-buildmode=c-shared', '-o',
     "#{ext_dir}/#{library_name.call(Gem.win_platform? ? 'windows' : '')}", 'main.go'
end

desc 'Build Proscenium gems into the pkg directory.'
task build: [:clobber] + PLATFORMS.keys.map { |platform| "build:#{platform}" }

desc 'Push Proscenium gems up to the gem server.'
task push: PLATFORMS.keys.map { |platform| "push:#{platform}" } << 'push:gem'

PLATFORMS.each do |ruby_platform, go_platform|
  task "build:#{ruby_platform}" => ["compile:#{ruby_platform}"] do
    # Set for this subprocess only. Exporting it would defeat the point: `rake build` builds the
    # platform gems and then the platform-less one in a single process, and the plain gem must
    # not see it. See the gate in the gemspec.
    sh({ 'PROSCENIUM_PACKAGE_EXT' => '1' }, 'gem', 'build', '-V', '--platform', ruby_platform) do
      gem_path = Gem::Util.glob_files_in_dir("proscenium-*-#{ruby_platform}.gem",
                                             base).max_by do |f|
        File.mtime(f)
      end

      FileUtils.mkdir_p pkg_dir
      FileUtils.mv gem_path, 'pkg'

      puts ''
      puts "---> Built #{gemspec.version} to pkg/proscenium-#{gemspec.version}-#{ruby_platform}.gem"
    end
  end

  desc "Compile for #{ruby_platform}"
  task "compile:#{ruby_platform}" => 'clobber:ext' do
    puts ''
    puts "---> Compiling for #{ruby_platform} (#{go_platform})"

    goos, goarch = go_platform.split('/')

    if NATIVE_GOOS.include?(goos)
      # Environment as a hash rather than a `VAR=value` prefix, which cmd.exe does not understand.
      sh({ 'GOWORK' => 'off', 'GOOS' => goos, 'GOARCH' => goarch, 'CGO_ENABLED' => '1' },
         'go', 'build', '-buildmode=c-shared', '-v', '-o',
         "#{ext_dir}/#{library_name.call(goos)}", 'main.go')
    else
      sh %(xgo -env=GOWORK=off -buildmode=c-shared -dest="#{ext_dir}" -targets="#{go_platform}" .)

      built_path.each_child do |child|
        if child.extname == '.h'
          child.rename "#{ext_dir}/proscenium.h"
        else
          child.rename "#{ext_dir}/proscenium"
        end
      end

      built_path.rmtree
    end
  end

  desc "Push built gem (#{ruby_platform})"
  task "push:#{ruby_platform}" do
    push_gem.call("pkg/proscenium-#{gemspec.version}-#{ruby_platform}.gem")
  end
end

# Outside the loop above. Rake appends actions to an existing task rather than replacing it, so
# defining this once per platform gave it one action per platform - and `rake push` pushed the
# plain gem four times, prompting for an OTP on each and failing every attempt after the first.
desc 'Push built gem'
task 'push:gem' do
  push_gem.call("pkg/proscenium-#{gemspec.version}.gem")
end

desc 'Clobber ext'
task 'clobber:ext' do
  ext_path.rmtree
end

Rake::Task['clobber'].tap do |task|
  task.enhance ['clobber:ext']
end
