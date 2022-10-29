# frozen_string_literal: true

require 'rake/testtask'
require 'rake/clean'
require 'rubocop/rake_task'
require 'down'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

RuboCop::RakeTask.new
CLOBBER.include 'pkg'

task default: %i[test rubocop]
task release: %i[build push]

LIGHTNINGCSS_VERSION = '1.16.0'
PLATFORMS = {
  'x86_64-linux' => {
    deno: 'x86_64-unknown-linux-gnu',
    npm: 'linux-x64-gnu'
  },
  'x86_64-darwin' => {
    deno: 'x86_64-apple-darwin',
    npm: 'darwin-x64'
  },
  'arm64-darwin' => {
    deno: 'aarch64-apple-darwin',
    npm: 'darwin-arm64'
  }
}

desc 'Build Proscenium gems into the pkg directory.'
task build: [:clobber] + PLATFORMS.keys.map { |platform| "build:#{platform}" }

desc 'Push Proscenium gems up to the gem server.'
task push: PLATFORMS.keys.map { |platform| "push:#{platform}" }

# rubocop:disable Metrics/BlockLength
PLATFORMS.each do |platform, values|
  base = FileUtils.pwd
  pkg_dir = File.join(base, 'pkg')
  gemspec = Bundler.load_gemspec('proscenium.gemspec')

  task "build:#{platform}" => ["compile:esbuild:#{platform}",
                               "lightningcss:download:#{platform}"] do
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

  task "compile:esbuild:#{platform}" => 'clobber:bin:esbuild' do
    puts ''
    sh 'deno', 'compile', '--no-config', '-o', 'bin/esbuild', '--import-map', 'import_map.json',
       '-A', '--target', values[:deno], 'lib/proscenium/compilers/esbuild.js'
  end

  task "push:#{platform}" do
    sh 'gem', 'push', "pkg/proscenium-#{gemspec.version}-#{platform}.gem"
  end

  task "lightningcss:download:#{platform}" => 'clobber:bin:lightningcss' do
    puts "Downloading lightningcss from NPM for #{platform}..."

    url = "lightningcss-cli-#{values[:npm]}/-/lightningcss-cli-#{values[:npm]}-#{LIGHTNINGCSS_VERSION}.tgz"
    file = Down.download("https://registry.npmjs.org/#{url}")

    filename = "lightningcss-cli-#{values[:npm]}-#{LIGHTNINGCSS_VERSION}.tgz"
    FileUtils.mv file, "tmp/#{filename}"

    FileUtils.cd 'tmp' do
      sh 'tar', '-xzf', filename, 'package/lightningcss'
    end

    FileUtils.mv 'tmp/package/lightningcss', 'bin/lightningcss'
    FileUtils.chmod '+x', 'bin/lightningcss'
  end
end
# rubocop:enable Metrics/BlockLength

task 'clobber:bin' => ['clobber:bin:esbuild', 'clobber:bin:lightningcss']
task 'clobber:bin:esbuild' do
  FileUtils.rm 'bin/esbuild', force: true
end
task 'clobber:bin:lightningcss' do
  FileUtils.rm 'bin/lightningcss', force: true
end

Rake::Task['clobber'].tap do |task|
  task.enhance ['clobber:bin']
end
