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

    refute root.start_with?(File.expand_path('../..', __dir__)), 'installed, not the source tree'
    assert_equal '/node_modules/@rubygems/stage_a_widget_b/index.js', url
    assert_includes code, '/node_modules/.pnpm/ms@2.1.3/node_modules/ms/index.js'
  end

  # C34
  it 'refuses to build while an install is in progress' do
    Adopted.with_file('.proscenium/installing', '1') do
      message, = Adopted.run(refusal(WIDGET))

      assert_includes message, '`bundle exec proscenium install` is running'
    end
  end

  # C45-C: the engine names the stale gem. A context written for another version of the gem has
  # that version's projection hash.
  it 'refuses to build while a context is stale, naming the gem' do
    path = '.proscenium/packages/stage_a_widget_a/package.json'
    stale = File.read(File.join(Adopted::ROOT, path))
                .sub(/"projectionSha256": "\h+"/, '"projectionSha256": "older"')
    Adopted.with_file(path, stale) do
      message, log = Adopted.run(refusal('lib/app.js'))

      expected = 'stage_a_widget_a: its JavaScript dependencies changed since its context ' \
                 'was written'

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
