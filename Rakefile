# frozen_string_literal: true

require 'rake/testtask'
require 'rake/clean'
require 'rubocop/rake_task'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

RuboCop::RakeTask.new
CLOBBER.include 'pkg'

task default: %i[test rubocop]
task release: %i[build push]

PLATFORMS = {
  'x86_64-darwin' => { goos: 'darwin', arch: 'amd64' },
  'arm64-darwin' => { goos: 'darwin', arch: 'arm64' },
  'arm-linux' => { goos: 'linux', arch: 'arm' },
  'aarch64-linux' => { goos: 'linux', arch: 'arm64' },
  'x86_64-linux' => { goos: 'linux', arch: 'amd64' }
  # 'arm-windows' => { goos: 'windows', arch: 'arm' },
  # 'x86_64-windows' => { goos: 'windows', arch: 'amd64' },
  # 'aarch64-windows' => { goos: 'windows', arch: 'arm64' }
}.freeze

desc 'Compile for local os/arch'
task 'compile:local' => 'clobber:bin' do
  `go build -buildmode=c-shared -v -o bin/proscenium main.go`
end

desc 'Build Proscenium gems into the pkg directory.'
task build: [:clobber] + PLATFORMS.keys.map { |platform| "build:#{platform}" }

desc 'Push Proscenium gems up to the gem server.'
task push: PLATFORMS.keys.map { |platform| "push:#{platform}" }

PLATFORMS.each do |platform, values|
  base = FileUtils.pwd
  pkg_dir = File.join(base, 'pkg')
  gemspec = Bundler.load_gemspec('proscenium.gemspec')

  task "build:#{platform}" => ["compile:#{platform}"] do
    sh 'gem', 'build', '-V', '--platform', platform do
      gem_path = Gem::Util.glob_files_in_dir("proscenium-*-#{platform}.gem", base).max_by do |f|
        File.mtime(f)
      end

      FileUtils.mkdir_p pkg_dir
      FileUtils.mv gem_path, 'pkg'

      puts ''
      puts "---> Built #{gemspec.version} to pkg/proscenium-#{gemspec.version}-#{platform}.gem"
    end
  end

  desc "Compile for #{platform}"
  task "compile:#{platform}" => 'clobber:bin' do
    puts ''
    puts "---> Compiling for #{platform}"
    sh %(GOOS=#{values[:goos]} GOARCH=#{values[:arch]} go build -v --buildmode=c-shared -o bin/proscenium.so main.go)
  end

  desc "Push built gem (#{platform})"
  task "push:#{platform}" do
    sh 'gem', 'push', "pkg/proscenium-#{gemspec.version}-#{platform}.gem"
  end
end

desc 'Clobber bin'
task 'clobber:bin' do
  FileUtils.rm 'bin/proscenium.h', force: true
  FileUtils.rm 'bin/proscenium.so', force: true
end

Rake::Task['clobber'].tap do |task|
  task.enhance ['clobber:bin']
end
