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

PARCEL_VERSION = '1.3.0'
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
       '-A', '--target', values[:deno], 'lib/proscenium/compilers/esbuild.js'
  end

  task "push:#{platform}" do
    sh 'gem', 'push', "pkg/proscenium-#{gemspec.version}-#{platform}.gem"
  end

  task "parcel_css:download:#{platform}" do
    puts "Downloading parcel_css from NPM for #{platform}..."

    url = "@parcel/css-cli-#{values[:npm]}/-/css-cli-#{values[:npm]}-#{PARCEL_VERSION}.tgz"
    file = Down.download("https://registry.npmjs.org/#{url}")

    filename = "parcel-css-cli-#{values[:npm]}-#{PARCEL_VERSION}.tgz"
    FileUtils.mv file, "tmp/#{filename}"

    FileUtils.cd 'tmp' do
      sh 'tar', '-xzf', filename, 'package/parcel_css'
    end

    FileUtils.mv 'tmp/package/parcel_css', 'bin/parcel_css'
    FileUtils.chmod '+x', 'bin/parcel_css'
  end
end
# rubocop:enable Metrics/BlockLength

task 'clobber:bin' do
  FileUtils.rm 'bin/esbuild', force: true
  # FileUtils.rm 'bin/parcel_css', force: true
end

Rake::Task['clobber'].tap do |task|
  task.enhance ['clobber:bin']
end
