# frozen_string_literal: true

require_relative 'helper'
require_relative '../support/subprocess'
require 'rbconfig'

# The CLI must never load the engine (C37): not `proscenium` itself, ActiveSupport, Rails, FFI or
# Proscenium::Builder. Checked in a fresh process, since this one may already have loaded them.
describe 'CLI load isolation' do
  ISOLATION_LIB = File.expand_path('../../lib', __dir__)
  FORBIDDEN = %w[ActiveSupport Rails FFI Proscenium::Builder].freeze

  # Runs `proscenium` with `argv` in a clean Ruby process, after `preamble`, and returns the names
  # of the forbidden constants loaded by the end.
  def loaded_after(argv, preamble: '')
    script = <<~RUBY
      #{preamble}
      require 'proscenium/cli'
      require 'proscenium/cli/manager'
      Proscenium::CLI.start(#{argv.inspect}, out: StringIO.new, err: StringIO.new)
      puts #{FORBIDDEN.inspect}.select { |name| Object.const_defined?(name) }
    RUBY
    out, err, status = Subprocess.capture(RbConfig.ruby, '-I', ISOLATION_LIB, '-rstringio', '-e',
                                          script)
    raise "subprocess failed:\n#{out}#{err}" unless status.success?

    out.split
  end

  it 'loads none of the engine for --version' do
    assert_empty loaded_after(%w[--version])
  end

  it 'loads none of the engine for gem check' do
    gem = File.expand_path('../package_manager/stage_a/gems/stage_a_widget_a', __dir__)

    assert_empty loaded_after(['gem', 'check', gem])
  end

  it 'loads none of the engine for an error' do
    assert_empty loaded_after(%w[frobnicate])
  end

  # The control: requiring the engine first must be seen, or the check above proves nothing.
  it 'sees the engine when something loads it' do
    assert_includes loaded_after(%w[--version], preamble: "require 'proscenium'"), 'ActiveSupport'
  end
end

# The other direction: the engine reaches the model through Contexts::Stale, and must load nothing
# of the CLI. Every file under cli/ (the package manager, install, verify, the exit statuses) is
# the CLI's own.
describe 'Engine load isolation' do
  ENGINE_LIB = File.expand_path('../../lib', __dir__)

  # The files under lib/proscenium/cli/ loaded after requiring `feature` in a clean process.
  def cli_files_after(feature)
    script = "require #{feature.inspect}; " \
             'puts $LOADED_FEATURES.grep(%r{/lib/proscenium/cli/}).map { File.basename(it) }.sort'
    out, err, status = Subprocess.capture(RbConfig.ruby, '-I', ENGINE_LIB, '-e', script)
    raise "subprocess failed:\n#{out}#{err}" unless status.success?

    out.split
  end

  it 'loads nothing from the CLI' do
    assert_empty cli_files_after('proscenium/contexts/stale')
  end

  # The control: a CLI command must be seen, or the check above proves nothing.
  it 'sees the CLI when something loads it' do
    assert_includes cli_files_after('proscenium/cli/install'), 'manager.rb'
  end
end

# The model's files are required directly by the CLI, and by the engine through the autoload table
# in contexts.rb. A file that defined Contexts before `proscenium` registered that table once left
# its autoloads unset: the CLI tests passed, and Rails boot raised NameError.
describe 'Contexts autoload table' do
  CONTEXTS_LIB = File.expand_path('../../lib', __dir__)

  # Value: protects=the engine reaching every Contexts file after a CLI-style direct require
  # loaded one first; fails_when=proscenium.rb stops requiring contexts.rb eagerly, or a file in
  # contexts/ is missing from its table; why_new=every other test loads one order only, the
  # engine first (test_helper) or the CLI alone; seam=none; no_claim=says nothing of Rails boot
  it 'resolves every model file, whichever of them is required before the engine' do
    names = Dir[File.join(CONTEXTS_LIB, 'proscenium/contexts/*.rb')]
            .map { File.basename(it, '.rb').split('_').map(&:capitalize).join }.sort
    script = "require 'proscenium/contexts/map'; require 'proscenium'; " \
             "puts #{names.inspect}.map { |n| Proscenium::Contexts.const_get(n).name }"
    out, err, status = Subprocess.capture(RbConfig.ruby, '-I', CONTEXTS_LIB, '-e', script)

    assert_predicate status, :success?, "#{out}#{err}"
    assert_equal names.map { "Proscenium::Contexts::#{it}" }, out.split
  end
end
