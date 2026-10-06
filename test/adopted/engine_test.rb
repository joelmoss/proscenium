# frozen_string_literal: true

require_relative 'helper'

# The engine in an app that has adopted gem dependency contexts (#154, Stage C), with real gems
# installed by Bundler and dependencies installed by pnpm 11 from the committed lock.
describe 'an adopted app' do
  before do
    skip 'set STAGE_A=1 to run (needs pnpm)' unless ENV['STAGE_A']
    Adopted.setup!
  end

  WIDGET = 'node_modules/@rubygems/stage_a_widget_a/index.js'
  REACT = '/node_modules/.pnpm/react@18.3.1/node_modules/react/index.js'

  def build(path) = "Proscenium::Builder.build_to_string(#{path.inspect}, Bundle: false)[:response]"

  def refusal(path) = "begin; #{build(path)}; rescue Proscenium::Error => e; e.message; end"

  # C02 and C49: the gem pins ms 2.0.0, the app 2.1.3. The gem gets its own, from its context,
  # and shares the app's one React.
  it "resolves a gem's dependencies from its context, sharing the app's React" do
    (widget, app), = Adopted.run("[#{build(WIDGET)}, #{build('lib/app.js')}]")

    assert_includes widget, '/node_modules/.pnpm/ms@2.0.0/node_modules/ms/index.js'
    assert_includes app, '/node_modules/.pnpm/ms@2.1.3/node_modules/ms/index.js'
    assert_includes widget, REACT
    assert_includes app, REACT
  end

  # The app's own pnpm workspace sibling keeps its link path, not its real one under packages/.
  it "keeps the URL of the app's own workspace package" do
    app, = Adopted.run(build('lib/app.js'))

    assert_includes app, '"/node_modules/sibling/index.js"'
  end

  # C01: gems that do not participate get no context and are served in place, as before. A
  # self-contained one works alone; one that imports an undeclared package gets the app's copy.
  it 'serves gems that do not participate in place, with the app\'s packages' do
    gems = %w[stage_a_assets stage_a_app_dependent].map { "node_modules/@rubygems/#{it}/index.js" }
    (assets, dependent), = Adopted.run("[#{gems.map { build(it) }.join(', ')}]")

    assert_includes assets, '/node_modules/@rubygems/stage_a_assets/util.js'
    assert_includes dependent, '/node_modules/.pnpm/ms@2.1.3/node_modules/ms/index.js'
    assert_equal %w[stage_a_widget_a stage_a_widget_b],
                 Dir.children(File.join(Adopted::ROOT, '.proscenium/packages')).sort
  end

  # C03: an archive gem, installed outside the app like any registry gem, keeps the same URL as a
  # path gem, and its dependencies come from its context.
  it 'serves an installed archive gem at its usual URL, from its installed copy' do
    (root, url, code), = Adopted.run(
      "gem = 'stage_a_widget_b'; root = Proscenium::BundledGems.paths[gem]; " \
      "[root, Proscenium::Resolver.resolve(File.join(root, 'index.js')), " \
      "#{build('node_modules/@rubygems/stage_a_widget_b/index.js')}]"
    )

    refute root.start_with?(StageA::Bundle::GEMS), 'installed, not its source'
    assert_equal 'stage_a_widget_b-1.0.0', File.basename(root)
    assert_equal '/node_modules/@rubygems/stage_a_widget_b/index.js', url
    assert_includes code, '/node_modules/.pnpm/ms@2.1.3/node_modules/ms/index.js'
  end

  # C23: precompiling for a deploy builds through the contexts and writes the manifest, and it is
  # where stale contexts stop a deploy.
  it 'precompiles through the contexts, and refuses to while a context is stale' do
    compile = "Proscenium::Builder.compile(Precompile: ['lib/app.js', '#{WIDGET}']); " \
              "JSON.parse(File.read('public/assets/.manifest.json'))['outputs'].keys"
    outputs, = Adopted.run(compile)
    outputs = outputs.map { it.tr('\\', '/') } # esbuild writes Windows paths with backslashes

    assert_includes outputs.join("\n"), 'lib/app-$'
    assert_includes outputs.join("\n"), '@rubygems/stage_a_widget_a/index-$'

    path = '.proscenium/packages/stage_a_widget_a/package.json'
    stale = File.read(File.join(Adopted::ROOT, path))
                .sub(/"projectionSha256": "\h+"/, '"projectionSha256": "older"')
    Adopted.with_file(path, stale) do
      message, = Adopted.run("begin; #{compile}; rescue Proscenium::Error => e; e.message; end")

      assert_includes message, 'Gem dependency contexts are out of date'
    end
  ensure
    FileUtils.rm_rf(File.join(Adopted::ROOT, 'public'))
  end

  # C24: `bun test` builds through the same daemon, so the gem's imports come from its context
  # there too (fixtures/adopted/test/js/widget.test.js).
  it "resolves a gem's imports from its context under bun test" do
    assert_includes Adopted.sh('bun', 'test', 'test/js/'), '1 pass'
  end

  # C54: on a Heroku-style platform the Node buildpack may run before the Ruby one. The contexts
  # are committed, so the native frozen install needs no gems, and once both have run, the
  # documented check passes. Setup ran them Ruby first; this runs Node first.
  it 'installs with Node before Ruby, then passes `proscenium install --frozen`' do
    FileUtils.rm_rf(Dir[File.join(Adopted::ROOT, '{,.proscenium/packages/*/}node_modules')])
    Adopted.sh('pnpm', 'install', '--frozen-lockfile')
    Adopted.sh('bundle', 'install', '--local', '--quiet')

    assert_includes Adopted.sh('bundle', 'exec', 'proscenium', 'install', '--frozen'),
                    'Everything is up to date'
  end

  # C34
  it 'refuses to build while an install is in progress' do
    Adopted.with_file('.proscenium/installing', '1') do
      message, = Adopted.run(refusal(WIDGET))

      assert_includes message, '`bundle exec proscenium install` is running'
    end
  end

  # C45-C: the engine names the stale gem. A context written for another version of the gem
  # holds that version's dependencies, and the projection hash that matches them.
  it 'refuses to build while a context is stale, naming the gem' do
    path = '.proscenium/packages/stage_a_widget_a/package.json'
    older = JSON.parse(File.read(File.join(Adopted::ROOT, path)))
    older['dependencies'] = older['dependencies'].merge('ms' => '1.0.0')
    stale = Proscenium::DependencyContext.to_json(
      Proscenium::DependencyContext.project('stage_a_widget_a', older)
    )
    Adopted.with_file(path, stale) do
      message, log = Adopted.run(refusal('lib/app.js'))

      expected = 'stage_a_widget_a: its NPM dependencies changed since its dependency ' \
                 'context was written'

      assert_includes message, expected
      assert_includes message, 'Run `bundle exec proscenium install`'
      assert_includes log, expected, 'logged at boot in development and test'
    end
  end

  # C52: before adoption the gem resolves as it always has, and boot says what to run.
  it 'keeps the old resolution before adoption, and logs the notice' do
    Adopted.with_file('pnpm-workspace.yaml', "packages: []\n") do
      widget, log = Adopted.run(build(WIDGET))

      refute_includes widget, 'ms@2.0.0'
      assert_includes log, 'stage_a_widget_a, stage_a_widget_b opt in to installing their'
    end
  end
end
