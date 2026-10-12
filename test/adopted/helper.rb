# frozen_string_literal: true

require_relative '../cli/helper'
require_relative '../support/subprocess'
require 'json'
require 'tmpdir'
require 'rbconfig'
require_relative '../package_manager/stage_a/bundle'

# fixtures/adopted, an app that has adopted gem dependency contexts (#154, Stage C), driven as a
# subprocess: its own Gemfile sets Bundler.root, which the engine reads contexts from, and this
# suite's own bundle (or an Appraisal gemfile) would set it elsewhere.
#
# Runs only with STAGE_A=1: setting it up runs pnpm, as the package-manager CI job can.
module Adopted
  ROOT = File.expand_path('../../fixtures/adopted', __dir__)

  module_function

  def env
    # Frozen, so installing never rewrites the committed lock, and Bundler checks every gem
    # against the checksums it holds.
    env = { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'RAILS_ENV' => 'test',
            'BUNDLE_FROZEN' => 'true' }
    # CI installs gems into a bundle path; the fixture's gems are the same versions.
    path = Bundler.settings[:path]
    env['BUNDLE_PATH'] = File.expand_path(path, Bundler.root) if path
    env
  end

  # Installs the fixture's gems and runs a frozen native install, once per process: a fresh
  # checkout of an adopted app needs nothing else (C45). stage_a_widget_b is an archive gem in
  # vendor/cache, as a registry would serve it. It is committed rather than built here: RubyGems
  # versions build different bytes, and Gemfile.lock holds its checksum.
  def setup!
    @setup ||= begin
      gem = File.join(ROOT, 'vendor/cache/stage_a_widget_b-1.0.0.gem')
      raise "#{gem} is committed, and its checksum is in Gemfile.lock" unless File.exist?(gem)

      sh('bundle', 'install', '--local', '--quiet')
      sh('pnpm', 'install', '--frozen-lockfile')
      true
    end
  end

  def sh(*command)
    out, err, status = capture(*command)
    raise "#{command.join(' ')} failed:\n#{out}#{err}" unless status.success?

    out + err
  end

  # A command's stdout, stderr and status, run in the fixture app outside this suite's bundle,
  # with Subprocess's deadline.
  def capture(*command)
    Bundler.with_unbundled_env { Subprocess.capture(*command, env:, chdir: ROOT) }
  end

  # Boots the app, evaluates `code` and returns its value, round-tripped through JSON, with the
  # process's stderr (the Rails log).
  def run(code)
    script = "require './config/environment'\n" \
             "result = begin\n#{code}\nend\n$stdout.write(JSON.generate(result))\n"
    out, err, status = capture(RbConfig.ruby, '-e', script)
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
