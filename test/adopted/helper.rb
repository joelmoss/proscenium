# frozen_string_literal: true

require_relative '../cli/helper'
require 'json'
require 'open3'
require 'rbconfig'
require_relative '../package_manager/stage_a/bundle'

# fixtures/adopted, an app that has adopted gem dependency contexts (#154, Stage C), driven as a
# subprocess: its own Gemfile sets Bundler.root, which the engine reads contexts from, and this
# suite's own bundle (or an Appraisal gemfile) would set it elsewhere.
#
# Runs only with STAGE_A=1: setting it up runs pnpm, as the stage-a CI job can.
module Adopted
  ROOT = File.expand_path('../../fixtures/adopted', __dir__)

  module_function

  def env
    env = { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'RAILS_ENV' => 'test' }
    # CI installs gems into a bundle path; the fixture's gems are the same versions.
    path = Bundler.settings[:path]
    env['BUNDLE_PATH'] = File.expand_path(path, Bundler.root) if path
    env
  end

  # Installs the fixture's gems and runs a frozen native install, once per process: a fresh
  # checkout of an adopted app needs nothing else (C45). stage_a_widget_b is an archive gem,
  # built into vendor/cache first, as a registry would serve it.
  def setup!
    @setup ||= begin
      cache = File.join(ROOT, 'vendor', 'cache')
      unless File.exist?(File.join(cache, 'stage_a_widget_b-1.0.0.gem'))
        FileUtils.mkdir_p(cache)
        StageA::Bundle.build(File.join(StageA::Bundle::GEMS, 'stage_a_widget_b'), cache)
      end
      sh('bundle', 'install', '--local', '--quiet')
      sh('pnpm', 'install', '--frozen-lockfile')
      true
    end
  end

  def sh(*command)
    out, status = Bundler.with_unbundled_env do
      Open3.capture2e(env, *command, chdir: ROOT)
    end
    raise "#{command.join(' ')} failed:\n#{out}" unless status.success?

    out
  end

  # Boots the app, evaluates `code` and returns its value, round-tripped through JSON, with the
  # process's stderr (the Rails log).
  def run(code)
    script = "require './config/environment'\n" \
             "result = begin\n#{code}\nend\n$stdout.write(JSON.generate(result))\n"
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3(env, RbConfig.ruby, '-e', script, chdir: ROOT)
    end
    raise "the adopted app failed:\n#{err}" unless status.success?

    [JSON.parse(out), err]
  end

  # Runs the block with `path` (relative to the app) holding `body`, restoring it after.
  def with_file(path, body)
    full = File.join(ROOT, path)
    before = File.exist?(full) ? File.binread(full) : nil
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
    yield
  ensure
    before ? File.binwrite(full, before) : FileUtils.rm_f(full)
  end
end
