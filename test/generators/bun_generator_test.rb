# frozen_string_literal: true

require 'test_helper'
require 'rails/generators/test_case'
require 'generators/proscenium/bun/bun_generator'

class Proscenium::Generators::BunGeneratorTest < Rails::Generators::TestCase
  tests Proscenium::Generators::BunGenerator
  destination Rails.root.join('tmp/generator_test')
  setup :prepare_destination

  def bunfig
    File.join(destination_root, 'bunfig.toml')
  end

  def write_bunfig(contents)
    File.write bunfig, contents
  end

  # No TOML parser is worth a dependency for one generator, so this asserts the two shapes that
  # actually corrupted a real bunfig - a duplicate `[test]` table and a stray comma - alongside the
  # entries themselves. Both produced a file that looked plausible and would not parse.
  def assert_preload(expected)
    contents = File.read(bunfig)
    table = contents[/^\[test\][^\n]*\n.*?(?=^\[|\z)/m]

    assert_equal 1, contents.scan(/^\[test\]/).size, "expected one [test] table:\n#{contents}"
    refute_nil table, "no [test] table:\n#{contents}"

    array = table[/^[^#\n]*\bpreload\s*=\s*\[(.*?)\]/m, 1]
    refute_nil array, "no [test] preload array:\n#{contents}"
    refute_match(/,\s*,/, array, "stray double comma:\n#{contents}")
    refute_match(/,\s*\z/, array, "trailing comma before ]:\n#{contents}")

    assert_equal expected, array.scan(/"([^"]+)"/).flatten
  end

  it 'creates the preload and a bunfig' do
    run_generator

    assert_file 'test/proscenium.preload.js', %r{proscenium/runtime/bootstrap\.js}
    assert_file 'bunfig.toml', %r{preload = \["\./test/proscenium\.preload\.js"\]}
  end

  it 'is safe to run twice' do
    run_generator
    before = File.read(File.join(destination_root, 'bunfig.toml'))

    run_generator ['--force']

    assert_equal before, File.read(File.join(destination_root, 'bunfig.toml'))
  end

  it 'merges into an existing preload list rather than clobbering it' do
    File.write File.join(destination_root, 'bunfig.toml'), <<~TOML
      [test]
      preload = ["./test/setup.js"]
    TOML

    run_generator

    assert_file 'bunfig.toml',
                %r{preload = \["\./test/setup\.js", "\./test/proscenium\.preload\.js"\]}
  end

  # Each of these produced an unparsable bunfig.toml, or edited the wrong array, from a generator
  # that promises it is safe to re-run. TOML is whitespace-tolerant inside an array but not about
  # duplicate tables or stray commas.
  it 'respects a trailing comma in a multi-line preload array' do
    write_bunfig <<~TOML
      [test]
      preload = [
        "./test/setup.js",
      ]
    TOML

    run_generator

    assert_preload ['./test/setup.js', './test/proscenium.preload.js']
  end

  it 'adds preload into an existing test table rather than declaring it twice' do
    write_bunfig "[test]\ncoverage = true\n"

    run_generator

    assert_preload ['./test/proscenium.preload.js']
    assert_equal 1, File.read(bunfig).scan('[test]').size
  end

  # A file whose last line is `[test]` with no trailing newline used to read as having no `[test]`
  # table at all, and the generator appended a second one - invalid TOML, and the exact shape this
  # rewrite exists to prevent. Refusing and printing the manual step is the safe answer.
  it 'refuses rather than declaring a second table when [test] ends the file unterminated' do
    write_bunfig "[install]\nfoo = 1\n[test]"

    run_generator

    assert_equal 1, File.read(bunfig).scan('[test]').size
    assert_equal "[install]\nfoo = 1\n[test]", File.read(bunfig)
  end

  it 'leaves a root-level preload alone - it belongs to bun run, not bun test' do
    write_bunfig %(preload = ["./run-setup.js"]\n\n[test]\ncoverage = true\n)

    run_generator

    assert_preload ['./test/proscenium.preload.js']
    assert_includes File.read(bunfig), %(preload = ["./run-setup.js"])
  end

  it 'does not report identical when the entry is only present commented out' do
    write_bunfig %([test]\n# preload = ["./test/proscenium.preload.js"]\n)

    run_generator

    assert_preload ['./test/proscenium.preload.js']
  end

  it 'appends a test section to a bunfig that has none' do
    File.write File.join(destination_root, 'bunfig.toml'), %([install]\nregistry = "x"\n)

    run_generator

    assert_file 'bunfig.toml', /\[install\]/
    assert_file 'bunfig.toml', %r{preload = \["\./test/proscenium\.preload\.js"\]}
  end
end
