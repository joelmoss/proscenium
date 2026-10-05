# frozen_string_literal: true

require_relative 'helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../package_manager/stage_a/bundle'
require_relative 'private_registry'
require_relative 'logging_proxy'

# C10 (#154): every kind of dependency spec a gem may declare (a range, a prerelease, a dist-tag,
# an npm: alias, a GitHub reference and a tarball URL) installs from the gem's context exactly as
# from a native workspace package declaring the same, in the same install. "Exactly" means the
# context and the native package reach the one same directory for each dependency.
#
# Runs only with STAGE_A=1: it needs pnpm, Bun and the network.
describe 'dependency spec kinds' do
  SPEC_KINDS_LIB = File.expand_path('../../lib', __dir__)
  SPEC_KINDS_EXE = File.expand_path('../../exe/proscenium', __dir__)
  GEM = 'stage_a_specs'
  SOURCE = File.join(StageA::Bundle::GEMS, GEM)
  MANIFEST = JSON.parse(File.read(File.join(SOURCE, 'package.json')))
  # The range, the prerelease and the alias, as resolved: ms 2.1.3 is the newest 2.x.
  VERSIONS = { 'ms' => '2.1.3', 'ms-beta' => '3.0.0-beta.2', 'ms-old' => '2.0.0' }.freeze

  before do
    skip 'set STAGE_A=1 to run (needs pnpm, Bun and the network)' unless ENV['STAGE_A']
    @dir = Dir.mktmpdir('spec_kinds')
  end

  after do
    StageA::Bundle.writable!(@dir) if @dir
    FileUtils.rm_rf(@dir) if @dir
  end

  # An app bundling only the fixture gem, installed as an archive, with a native workspace package
  # `packages/native` declaring the same dependencies. `source` is the gem's source directory.
  def app(manager, source = SOURCE, linker: 'isolated')
    app = File.join(@dir, 'app')
    cache = File.join(app, 'vendor', 'cache')
    FileUtils.mkdir_p(cache)
    StageA::Bundle.build(source, cache)
    name = File.basename(source)
    File.write(File.join(app, 'Gemfile'), "source 'https://rubygems.org'\ngem '#{name}'\n")
    StageA::Bundle.bundle(app, @dir, 'install', '--local')

    manifest = JSON.parse(File.read(File.join(source, 'package.json')))
    native = File.join(app, 'packages', 'native')
    FileUtils.mkdir_p(native)
    declared = manifest.slice('dependencies', 'optionalDependencies')
    File.write(File.join(native, 'package.json'),
               JSON.generate({ 'name' => 'native', 'private' => true }.merge(declared)))
    package = { 'name' => 'app', 'private' => true }
    if manager == 'bun'
      package['workspaces'] = ['packages/*']
      package['trustedDependencies'] = []
      File.write(File.join(app, 'bunfig.toml'), "[install]\nlinker = \"#{linker}\"\n")
    else
      package['packageManager'] = "pnpm@#{CLIHelper.pnpm_version}"
      File.write(File.join(app, 'pnpm-workspace.yaml'), "packages:\n  - packages/*\n")
    end
    File.write(File.join(app, 'package.json'), JSON.pretty_generate(package))
    app
  end

  def darwin? = RbConfig::CONFIG['host_os'].include?('darwin')

  def version(context, name)
    JSON.parse(File.read(File.join(context, 'node_modules', name, 'package.json')))['version']
  end

  def install(app, manager, env: {})
    Bundler.with_unbundled_env do
      Open3.capture3(StageA::Bundle.env(@dir).merge(env), RbConfig.ruby, '-I', SPEC_KINDS_LIB,
                     SPEC_KINDS_EXE, 'install', '--manager', manager, chdir: app)
    end
  end

  # An app whose gem declares `name`, from `registry`, under `field`, and which approves that
  # package's build, so its scripts run.
  def approved_app(manager, registry, name, field)
    app = app(manager, gem_source('stage_d_build', field => { name => '1.0.0' }))
    File.write(File.join(app, '.npmrc'), registry.npmrc)
    if manager == 'pnpm'
      File.write(File.join(app, 'pnpm-workspace.yaml'), "allowBuilds:\n  '#{name}': true\n",
                 mode: 'a')
    else
      package = JSON.parse(File.read(File.join(app, 'package.json')))
      File.write(File.join(app, 'package.json'),
                 JSON.generate(package.merge('trustedDependencies' => [name])))
    end
    app
  end

  # A gem source written for one case: `manifest` is its package.json.
  def gem_source(name, manifest)
    source = File.join(@dir, 'sources', name)
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = '#{name}'
        spec.version = '1.0.0'
        spec.summary = 'C14 fixture'
        spec.authors = ['Joel Moss']
        spec.files = %w[package.json]
        spec.metadata['proscenium.dependencies'] = 'true'
      end
    RUBY
    File.write(File.join(source, 'package.json'), JSON.generate(manifest))
    source
  end

  # A tarball the registry answers 404 for, so fetching it fails at once: a network error would
  # be retried for over a minute.
  UNFETCHABLE = 'https://registry.npmjs.org/left-pad/-/left-pad-0.0.0-absent.tgz'
  # How an app's environment names its proxy, in both spellings managers read (C31).
  PROXY_VARIABLES = %w[HTTP_PROXY HTTPS_PROXY http_proxy https_proxy].freeze
  # Where C14's failing build lands: the gem's context, and the native package declaring the same.
  BUILD_DIRS = %w[.proscenium/packages/stage_d_build packages/native].freeze

  # C47: the app importing a package only a gem declares. Recorded per linker, not reported: a
  # package reaches the app's own node_modules only under Bun's hoisted linker.
  { 'pnpm' => [nil, false], 'bun isolated' => ['isolated', false],
    'bun hoisted' => ['hoisted', true] }.each do |label, (linker, reachable)|
    it "records whether a gem-only package reaches the app on #{label}" do
      manager = label.split.first
      app = linker ? app(manager, linker:) : app(manager)
      FileUtils.rm_rf(File.join(app, 'packages')) # no native package declaring it too
      json = JSON.parse(File.read(File.join(app, 'package.json')))
      json['workspaces'] = json['workspaces'] - ['packages/*'] if json['workspaces']
      File.write(File.join(app, 'package.json'), JSON.generate(json))
      File.write(File.join(app, 'pnpm-workspace.yaml'), "packages: []\n") if manager == 'pnpm'
      _, err, status = install(app, manager)

      assert_predicate status, :success?, err
      assert_equal reachable, File.exist?(File.join(app, 'node_modules', 'clsx', 'package.json'))
    end
  end

  %w[pnpm bun].each do |manager|
    # C31: a gem depends on a package from a private registry. The app authenticates in its own
    # .npmrc, the manager uses that for the context too, the token appears in nothing Proscenium
    # writes or prints, and no request asks the registry for a gem.
    it "installs a private package with the app's own credentials, on #{manager}" do
      registry = PrivateRegistry.new
      app = app(manager, gem_source('stage_d_private', 'dependencies' =>
                                                       { PrivateRegistry::PACKAGE => '1.0.0' }))
      File.write(File.join(app, '.npmrc'), registry.npmrc)
      out, err, status = install(app, manager)

      assert_predicate status, :success?, err
      context = File.join(app, '.proscenium/packages/stage_d_private')

      assert_path_exists File.join(context, 'node_modules/@private/pkg/package.json')
      requests = registry.logged

      refute_empty requests
      assert_empty requests.reject { |_, authed| authed }, 'every request carried the token'
      assert_empty requests.select { |path, _| path.include?('rubygems') }, 'no gem was requested'
      written = [out, err, File.read(File.join(context, 'package.json')),
                 *Dir[File.join(app, '{pnpm-lock.yaml,bun.lock}')].map { File.read(it) }]

      assert(written.none? { it.include?(PrivateRegistry::TOKEN) }, 'the token leaked')
    ensure
      registry&.stop
    end

    # C31: the same, behind the proxy the app's environment names. The manager reaches the
    # registry through it, still with the app's credentials.
    it "installs a private package through a proxy, on #{manager}" do
      registry = PrivateRegistry.new
      proxy = LoggingProxy.new
      app = app(manager, gem_source('stage_d_proxied', 'dependencies' =>
                                                       { PrivateRegistry::PACKAGE => '1.0.0' }))
      File.write(File.join(app, '.npmrc'), registry.npmrc)
      env = PROXY_VARIABLES.to_h { [it, proxy.url] }
      out, err, status = install(app, manager, env: env.merge('NO_PROXY' => '', 'no_proxy' => ''))

      assert_predicate status, :success?, err
      assert_path_exists File.join(app, '.proscenium/packages/stage_d_proxied/node_modules',
                                   PrivateRegistry::PACKAGE, 'package.json')
      assert(proxy.logged.any? { it.include?("127.0.0.1:#{registry.port}") },
             'the registry was reached through the proxy')
      refute_includes out + err, PrivateRegistry::TOKEN
    ensure
      registry&.stop
      proxy&.stop
    end

    # C14: an optional dependency that cannot be fetched is left out, natively and from the
    # context alike, and the same dependency, required, still fails the install, naming the gem.
    it "skips an unfetchable optional dependency and fails on a required one, on #{manager}" do
      app = app(manager, gem_source('stage_d_optional', 'optionalDependencies' =>
                                                        { 'left-pad' => UNFETCHABLE }))
      _, err, status = install(app, manager)

      assert_predicate status, :success?, err
      refute_path_exists File.join(app,
                                   '.proscenium/packages/stage_d_optional/node_modules/left-pad')

      FileUtils.rm_rf(Dir.children(@dir).map { File.join(@dir, it) })
      app = app(manager, gem_source('stage_d_required', 'dependencies' =>
                                                        { 'left-pad' => UNFETCHABLE }))
      _, err, status = install(app, manager)

      assert_equal 6, status.exitstatus, err
      assert_includes err, 'PSM-E-NATIVE'
    end

    # C14: an optional dependency whose build fails, once the app has approved that build, is
    # treated in the context as natively; the same dependency, required, fails the install.
    it "treats an optional dependency whose build fails as natively, on #{manager}" do
      broken = '@private/broken'
      registry = PrivateRegistry.new(broken => { 'scripts' => { 'postinstall' => 'exit 1' } })
      app = approved_app(manager, registry, broken, 'optionalDependencies')
      _, err, status = install(app, manager)

      assert_predicate status, :success?, err
      present = BUILD_DIRS.map do |dir|
        File.exist?(File.join(app, dir, 'node_modules', broken, 'package.json'))
      end

      assert_equal present.first, present.last, 'the context and the native package differ'

      FileUtils.rm_rf(Dir.children(@dir).map { File.join(@dir, it) })
      app = approved_app(manager, registry, broken, 'dependencies')
      _, err, status = install(app, manager)

      assert_equal 6, status.exitstatus, err
      assert_includes err, 'PSM-E-NATIVE'
      assert_includes err, 'postinstall', 'the failure is the build, which the approval let run'
    ensure
      registry&.stop
    end

    it "installs each spec kind from the context as natively, on #{manager}" do
      app = app(manager)
      _, err, status = install(app, manager)

      assert_predicate status, :success?, err

      context = File.join(app, '.proscenium', 'packages', GEM)
      native = File.join(app, 'packages', 'native')
      MANIFEST['dependencies'].each_key do |name|
        from_context = File.realpath(File.join(context, 'node_modules', name))
        from_native = File.realpath(File.join(native, 'node_modules', name))

        assert_equal from_native, from_context, "#{name} differs between the context and native"
      end

      assert_equal(VERSIONS.values, VERSIONS.keys.map { version(context, it) })

      # C15: fsevents runs only on macOS. Each host installs the variant it can run, and omits
      # an optional one it cannot, the same for the context as natively.
      fsevents = ->(dir) { File.exist?(File.join(dir, 'node_modules/fsevents/package.json')) }
      installed = { 'context' => fsevents.call(context), 'native' => fsevents.call(native) }

      assert_equal({ 'context' => darwin?, 'native' => darwin? }, installed)
      refute JSON.parse(File.read(File.join(context, 'package.json'))).key?('version'),
             "the gem's manifest version is not the context's: Ruby and JS versions are independent"
    end
  end
end
