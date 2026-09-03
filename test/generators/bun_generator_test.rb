# frozen_string_literal: true

require 'test_helper'
require 'rails/generators/test_case'
require 'generators/proscenium/bun/bun_generator'

class Proscenium::Generators::BunGeneratorTest < Rails::Generators::TestCase
  tests Proscenium::Generators::BunGenerator
  destination Rails.root.join('tmp/generator_test')
  setup :prepare_destination

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

  it 'appends a test section to a bunfig that has none' do
    File.write File.join(destination_root, 'bunfig.toml'), %([install]\nregistry = "x"\n)

    run_generator

    assert_file 'bunfig.toml', /\[install\]/
    assert_file 'bunfig.toml', %r{preload = \["\./test/proscenium\.preload\.js"\]}
  end
end
