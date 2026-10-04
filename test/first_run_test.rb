# frozen_string_literal: true

require_relative 'cli/helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# C48 (#154): the first run, as a new user meets it. `rails new -j bun`, add Proscenium and one
# opted-in gem, `bundle install`, `bundle exec proscenium install`. Bun's trust list is the app's
# to declare, so install stops once to ask for it; then it pins the app's linker, installs, and
# the gem's component builds. Each step's wall time is printed against the 2-5 minute target.
#
# Runs only with FIRST_RUN=1: it generates a Rails app and installs its gems from the network.
describe 'the first run' do
  REPO = File.expand_path('..', __dir__)
  WIDGET_SOURCE = File.join(REPO, 'test/package_manager/stage_a/gems/stage_a_widget_a')

  before do
    skip 'set FIRST_RUN=1 to run (generates a Rails app from the network)' unless ENV['FIRST_RUN']
    @dir = Dir.mktmpdir('first_run')
    @times = {}
  end

  after { FileUtils.rm_rf(@dir) if @dir }

  # A command outside this suite's bundle, as a user's shell runs it, timed under `step`.
  def sh(step, *command, chdir:)
    env = { 'GEM_PATH' => Gem.path.join(File::PATH_SEPARATOR) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, status = Bundler.with_unbundled_env { Open3.capture2e(env, *command, chdir:) }
    @times[step] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    [out, status]
  end

  def sh!(step, *, chdir:)
    out, status = sh(step, *, chdir:)
    raise "#{step} failed:\n#{out}" unless status.success?

    out
  end

  it 'installs and builds a gem component after the documented commands' do
    rails = File.join(Gem.loaded_specs.fetch('railties').full_gem_path, 'exe', 'rails')
    sh!(:rails_new, RbConfig.ruby, rails, 'new', 'app', '-j', 'bun', '--skip-git', '--skip-test',
        '--skip-system-test', '--skip-active-record', '--skip-kamal', '--skip-thruster',
        '--skip-docker', '--skip-ci', '--skip-rubocop', '--skip-brakeman', chdir: @dir)
    app = File.join(@dir, 'app')
    File.write(File.join(app, 'Gemfile'), "\ngem 'proscenium', path: '#{REPO}'\n" \
                                          "gem 'stage_a_widget_a', path: '#{WIDGET_SOURCE}'\n",
               mode: 'a')
    sh!(:bundle_install, 'bundle', 'install', chdir: app)

    # With no package.json, the error names --manager.
    aside = %w[package.json bun.lock].to_h { [it, File.join(@dir, it)] }
    aside.each { |name, path| File.rename(File.join(app, name), path) }
    out, status = sh(:no_manager, 'bundle', 'exec', 'proscenium', 'install', chdir: app)
    aside.each { |name, path| File.rename(path, File.join(app, name)) }

    assert_equal 2, status.exitstatus, out
    assert_includes out, '--manager'

    out, status = sh(:first_install, 'bundle', 'exec', 'proscenium', 'install', chdir: app)

    assert_equal 3, status.exitstatus, out
    assert_includes out, 'PSM-E-BUN-TRUSTED'

    package = JSON.parse(File.read(File.join(app, 'package.json')))
    File.write(File.join(app, 'package.json'),
               JSON.pretty_generate(package.merge('trustedDependencies' => [])))
    out = sh!(:install, 'bundle', 'exec', 'proscenium', 'install', chdir: app)

    assert_includes out, '+linker = "hoisted"'
    assert_includes out, 'Installed JavaScript dependencies for 1 gems with bun'

    build = 'puts Proscenium::Builder.build_to_string(' \
            '"node_modules/@rubygems/stage_a_widget_a/index.js", Bundle: false)[:response]'
    out = sh!(:build, RbConfig.ruby, 'bin/rails', 'runner', build, chdir: app)

    assert_includes out, '/node_modules/ms/index.js'
  ensure
    warn "C48 #{RUBY_PLATFORM} seconds: #{@times}" if @times&.any?
  end
end
