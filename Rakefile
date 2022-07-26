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

PLATFORMS = {
  'x86_64-linux' => 'x86_64-unknown-linux-gnu',
  'x86_64-darwin' => 'x86_64-apple-darwin',
  'arm64-darwin' => 'aarch64-apple-darwin'
}

desc 'Build Proscenium gems into the pkg directory.'
task build: [:clobber] + PLATFORMS.keys.map { |platform| "build:#{platform}" }

desc 'Push Proscenium gems up to the gem server.'
task push: PLATFORMS.keys.map { |platform| "push:#{platform}" }

PLATFORMS.each do |platform, deno_platform|
  base = FileUtils.pwd
  pkg_dir = File.join(base, 'pkg')
  gemspec = Bundler.load_gemspec('proscenium.gemspec')

  task "build:#{platform}" => "compile:#{platform}" do
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

  task "compile:#{platform}" => "compile:esbuild:#{platform}"

  task "compile:esbuild:#{platform}" => 'clobber:bin' do
    puts ''
    sh 'deno', 'compile', '--no-config', '-o', 'bin/esbuild', '--import-map', 'import_map.json',
       '-A', '--target', deno_platform, 'lib/proscenium/compilers/esbuild.js'
  end

  task "push:#{platform}" do
    sh 'gem', 'push', "pkg/proscenium-#{gemspec.version}-#{platform}.gem"
  end
end

task 'clobber:bin' do
  FileUtils.rm 'bin/esbuild', force: true
end

Rake::Task['clobber'].tap do |task|
  task.enhance ['clobber:bin']
end
