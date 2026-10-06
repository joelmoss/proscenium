# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'

# What install checks after the manager runs (#154, C45, C55, C12): no gem from a registry, every
# context installed, and shared peers as one copy.
describe Proscenium::CLI::Verify do
  Manager = Struct.new(:name)

  before { @root = Dir.mktmpdir('verify') }
  after { FileUtils.rm_rf(@root) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), body)
  end

  def verify(manager, gems = ['widget'])
    Proscenium::CLI::Verify.new(@root, Manager.new(manager), gems)
  end

  def code(&) = assert_raises(Proscenium::CLI::Error, &).code

  PNPM_LOCK = <<~YAML
    lockfileVersion: '9.0'

    importers:

      .:
        dependencies:
          '@rubygems/widget':
            specifier: workspace:*
            version: link:.proscenium/packages/widget

      .proscenium/packages/widget:
        dependencies:
          ms:
            specifier: ^2.1.3
            version: 2.1.3

    packages:

      ms@2.1.3:
        resolution: {integrity: sha512-x}
  YAML

  BUN_LOCK = <<~JSONC
    {
      "lockfileVersion": 1,
      "workspaces": {
        "": { "name": "app", },
        ".proscenium/packages/widget": { "name": "@rubygems/widget", "dependencies": { "ms": "^2.1.3", }, },
      },
      "packages": {
        "@rubygems/widget": ["@rubygems/widget@workspace:.proscenium/packages/widget"],
        "ms": ["ms@2.1.3", "", {}, "sha512-x"],
      }
    }
  JSONC

  it 'accepts contexts linked as workspaces' do
    write('pnpm-lock.yaml', PNPM_LOCK)
    write('bun.lock', BUN_LOCK)
    write('.proscenium/packages/widget/package.json', '{}')

    verify('pnpm').call
    verify('bun').call
    pass
  end

  it 'refuses a gem resolved from a registry or a GitHub pin (exit 5)' do
    write('pnpm-lock.yaml',
          "#{PNPM_LOCK}\n  '@rubygems/widget@0.2.1':\n    resolution: {integrity: x}\n")
    write('bun.lock', BUN_LOCK.sub('"@rubygems/widget@workspace:.proscenium/packages/widget"',
                                   '"@rubygems/widget@0.2.1", "", {}, "sha512-y"'))

    assert_equal('PSM-E-REGISTRY-TARBALL', code do
      verify('pnpm').check_registry(File.read(File.join(@root, 'pnpm-lock.yaml')))
    end)
    assert_equal('PSM-E-REGISTRY-TARBALL', code do
      verify('bun').check_registry(File.read(File.join(@root, 'bun.lock')))
    end)
  end

  it 'refuses a gem pinned to Git, as an app installed it before adopting (exit 5)' do
    ['git+ssh://git@github.com/harleytherapy/hue.git#22e6604',
     'git+https://git@github.com:harleytherapy/hue.git#22e6604',
     'https://codeload.github.com/harleytherapy/hue/tar.gz/22e6604'].each do |source|
      lock = "#{PNPM_LOCK}\n  '@rubygems/widget@#{source}':\n    resolution: {tarball: x}\n"

      assert_equal('PSM-E-REGISTRY-TARBALL', code { verify('pnpm').check_registry(lock) })
    end
    bun = BUN_LOCK.sub('"@rubygems/widget@workspace:.proscenium/packages/widget"',
                       '"@rubygems/widget@github:harleytherapy/hue#22e6604", {}, "x"')

    assert_equal('PSM-E-REGISTRY-TARBALL', code { verify('bun').check_registry(bun) })
  end

  # pnpm writes a context left with no dependencies, such as one whose only optional dependency
  # was skipped, on one line.
  it 'accepts a context with no dependencies' do
    lock = "#{PNPM_LOCK}\n  .proscenium/packages/empty: {}\n"

    verify('pnpm', %w[widget empty]).check_workspaces(lock)
    pass
  end

  it 'refuses a context the manager did not install' do
    assert_equal('PSM-E-WORKSPACE-MISSING', code do
      verify('pnpm', %w[widget other]).check_workspaces(PNPM_LOCK)
    end)
    assert_equal('PSM-E-WORKSPACE-MISSING', code do
      verify('bun', %w[widget other]).check_workspaces(BUN_LOCK)
    end)
  end

  describe 'peers' do
    before do
      skip 'symlinks need privileges on Windows' if Gem.win_platform?
      write('package.json', '{"dependencies": {"react": "18.3.1"}}')
      write('.proscenium/packages/widget/package.json',
            '{"peerDependencies": {"react": "^18.0.0"}}')
      write('node_modules/.store/react@18.3.1/package.json', '{}')
      FileUtils.ln_s(File.join(@root, 'node_modules/.store/react@18.3.1'),
                     File.join(@root, 'node_modules/react'))
    end

    it 'accepts one copy reached through two links' do
      FileUtils.mkdir_p(File.join(@root, '.proscenium/packages/widget/node_modules'))
      FileUtils.ln_s(File.join(@root, 'node_modules/.store/react@18.3.1'),
                     File.join(@root, '.proscenium/packages/widget/node_modules/react'))

      verify('pnpm').check_peers
    end

    it 'accepts a peer the context finds by walking up to the app' do
      verify('bun').check_peers
    end

    # StaleContexts and `install --frozen` name a broken context or app manifest; the peer check
    # has nothing to compare there, and must not raise.
    it 'skips a context or app manifest it cannot read' do
      context = '.proscenium/packages/widget/package.json'
      ['{not json', '[]', '{"peerDependencies": []}'].each do |text|
        write(context, text)
        verify('pnpm').check_peers
      end
      File.delete(File.join(@root, context))
      verify('pnpm').check_peers
      ['{"dependencies": "x"}', '[]', '{not json'].each do |text|
        write('package.json', text)
        verify('pnpm').check_peers
      end
    end

    it 'refuses two copies (exit 5)' do
      write('.proscenium/packages/widget/node_modules/react/package.json', '{}')

      error = assert_raises(Proscenium::CLI::Error) { verify('pnpm').check_peers }

      assert_equal ['PSM-E-PEER-SPLIT', 5], [error.code, error.exit_status]
      assert_includes error.message, 'widget and your app use different copies of react'
    end

    # pnpm installs the app's own peers at the root too, so a peer it declares only there counts.
    it 'refuses two copies of a peer the app declares only as a peer' do
      write('package.json', '{"peerDependencies": {"react": "^18.0.0"}}')
      write('.proscenium/packages/widget/node_modules/react/package.json', '{}')

      assert_equal('PSM-E-PEER-SPLIT', code { verify('pnpm').check_peers })
    end
  end
end

describe 'Proscenium::CLI::Install.blame' do
  CONTEXTS = {
    'widget' => '{"dependencies": {"left-pad": "^1.3.0", "ms": "^2.1.3"}}',
    'other' => '{"dependencies": {"clsx": "^2"}, ' \
               '"peerDependencies": {"@rubygems/widget": "workspace:*"}}'
  }.freeze

  it "names the gem that brought in the package a manager's failure names" do
    output = ' ERR_PNPM_NO_MATURE_MATCHING_VERSION  Version 1.3.0 (released today) of ' \
             'left-pad does not meet the minimumReleaseAge constraint'

    assert_equal [%w[widget left-pad]], Proscenium::CLI::Install.blame(CONTEXTS, output)
  end

  it 'names nothing for output without an error, or a name inside another' do
    assert_empty Proscenium::CLI::Install.blame(CONTEXTS, 'Progress: resolved ms, done')
    assert_empty Proscenium::CLI::Install.blame(CONTEXTS, 'ERR_PNPM_X  mslib failed')
  end
end
