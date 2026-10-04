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
    out, err, status = capture(*command)
    raise "#{command.join(' ')} failed:\n#{out}#{err}" unless status.success?

    out + err
  end

  # A command's stdout, stderr and status, or a failure naming it once it has run for TIMEOUT
  # seconds: a hang on one host fails its test rather than the whole CI job. The failure carries
  # what the command had printed. The whole process tree is killed, because `bun test` starts a
  # Rails daemon that holds the output pipes open.
  TIMEOUT = 180

  def capture(*command)
    Bundler.with_unbundled_env do
      out_r, out_w = IO.pipe
      err_r, err_w = IO.pipe
      pid = Process.spawn(env, *command, chdir: ROOT, in: File::NULL, out: out_w, err: err_w,
                                         **(Gem.win_platform? ? {} : { pgroup: true }))
      [out_w, err_w].each(&:close)
      out = drain(out_r)
      err = drain(err_r)
      waiter = Process.detach(pid)
      unless waiter.join(TIMEOUT)
        kill_tree(pid)
        raise "#{command.first(3).join(' ')} did not finish in #{TIMEOUT}s. It printed:\n" \
              "#{out.value_so_far}#{err.value_so_far}"
      end

      [out.value, err.value, waiter.value]
    end
  end

  # Reads `io` to its end in a thread, keeping what has arrived so far readable.
  def drain(io)
    buffer = +''
    thread = Thread.new do
      loop { buffer << io.readpartial(4096) }
    rescue IOError
      buffer
    end
    thread.define_singleton_method(:value_so_far) { buffer.dup }
    thread
  end

  def kill_tree(pid)
    if Gem.win_platform?
      system('taskkill', '/T', '/F', '/PID', pid.to_s, out: File::NULL, err: File::NULL)
    else
      Process.kill(:KILL, -pid)
    end
  rescue Errno::ESRCH
    nil
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
