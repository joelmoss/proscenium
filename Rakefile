# frozen_string_literal: true

require 'bundler/setup'

APP_RAKEFILE = File.expand_path('fixtures/dummy/Rakefile', __dir__)
load 'rails/tasks/engine.rake'

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rubocop/rake_task'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
  t.warning = false
end

RuboCop::RakeTask.new
CLOBBER.include 'pkg'

task default: %i[test rubocop]
task release: %i[build push]

#
# GO Binary                 | Ruby Gem
# --------------------------|---------------|
#
# darwin-10.12-arm64.dylib  | arm64-darwin  |
# darwin-10.12-amd64.dylib  | x86_64-darwin |
#
# linux-arm64.so            | aarch64-linux |
# linux-amd64.so            | x86_64-linux  |
#
# windows-4.0-386           | x86-mingw32   | ?
# windows-4.0-amd64         | x64-mingw32   | ?
#

# Ruby => Go
PLATFORMS = {
  'x86_64-darwin' => 'darwin/amd64',
  'arm64-darwin' => 'darwin/arm64',
  'aarch64-linux' => 'linux/arm64',
  'x86_64-linux' => 'linux/amd64'
  # 'arm-linux' => { goos: 'linux', arch: 'arm' },
  # 'x86-linux' => { goos: 'linux', arch: '386' },
  # 'x86_64-linux' => { goos: 'linux', arch: 'amd64' }
  # 'arm-windows' => { goos: 'windows', arch: 'arm' },
  # 'x86_64-windows' => { goos: 'windows', arch: 'amd64' },
  # 'aarch64-windows' => { goos: 'windows', arch: 'arm64' }
}.freeze

base = FileUtils.pwd
pkg_dir = File.join(base, 'pkg')
ext_dir = 'lib/proscenium/ext'
ext_path = Pathname.new(base).join(ext_dir)
built_path = ext_path.join('joelmoss')
gemspec = Bundler.load_gemspec('proscenium.gemspec')

desc 'Compile for local os/arch'
task 'compile:local' => 'clobber:ext' do
  sh %(go build -buildmode=c-shared -o #{ext_dir}/proscenium main.go)
end

desc 'Build Proscenium gems into the pkg directory.'
task build: [:clobber] + PLATFORMS.keys.map { |platform| "build:#{platform}" }

desc 'Push Proscenium gems up to the gem server.'
task push: PLATFORMS.keys.map { |platform| "push:#{platform}" }

PLATFORMS.each do |ruby_platform, go_platform|
  task "build:#{ruby_platform}" => ["compile:#{ruby_platform}"] do
    sh 'gem', 'build', '-V', '--platform', ruby_platform do
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

    if go_platform.include?('darwin')
      goos, goarch = go_platform.split('/')
      # rubocop:disable Layout/LineLength
      sh %(GOOS=#{goos} GOARCH=#{goarch} CGO_ENABLED=1 go build -buildmode=c-shared -v -o #{ext_dir}/proscenium main.go)
      # rubocop:enable Layout/LineLength
    else
      sh %(xgo -buildmode=c-shared -dest="#{ext_dir}" -targets="#{go_platform}" .)

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
    sh 'gem', 'push', "pkg/proscenium-#{gemspec.version}-#{ruby_platform}.gem"
  end
end

desc 'Clobber ext'
task 'clobber:ext' do
  ext_path.rmtree
end

Rake::Task['clobber'].tap do |task|
  task.enhance ['clobber:ext']
end
