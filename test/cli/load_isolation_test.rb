# frozen_string_literal: true

require_relative 'helper'
require 'open3'
require 'rbconfig'

# The CLI must never load the engine (C37): not `proscenium` itself, ActiveSupport, Rails, FFI or
# Proscenium::Builder. Checked in a fresh process, since this one may already have loaded them.
describe 'CLI load isolation' do
  LIB = File.expand_path('../../lib', __dir__)
  FORBIDDEN = %w[ActiveSupport Rails FFI Proscenium::Builder].freeze

  # Runs `proscenium` with `argv` in a clean Ruby process, after `preamble`, and returns the names
  # of the forbidden constants loaded by the end.
  def loaded_after(argv, preamble: '')
    script = <<~RUBY
      #{preamble}
      require 'proscenium/cli'
      Proscenium::CLI.start(#{argv.inspect}, out: StringIO.new, err: StringIO.new)
      puts #{FORBIDDEN.inspect}.select { |name| Object.const_defined?(name) }
    RUBY
    out, status = Open3.capture2e(RbConfig.ruby, '-I', LIB, '-rstringio', '-e', script)
    raise "subprocess failed:\n#{out}" unless status.success?

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
