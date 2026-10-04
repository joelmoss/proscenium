# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tmpdir'
require_relative 'bundle'
require_relative 'context'

# Does Stage A need a descriptor receipt (#154)? The plan keeps one only if committed native inputs
# cannot detect a changed locked gem source or revision, a changed projection version, or a changed
# registration. Each drift case below is applied alone to a clean app, and `Context.drift` must see
# it, or must see nothing when nothing a context records has changed, from the registration, the
# committed contexts and the installed gems alone.
class StageA::DriftTest < ActiveSupport::TestCase
  GEM = 'stage_a_widget_a'
  DIR = Dir.mktmpdir('stage_a_drift')
  Minitest.after_run do
    StageA::Bundle.writable!(DIR)
    FileUtils.rm_rf(DIR)
  end

  def self.root = @root ||= StageA::Bundle.install(DIR).fetch(GEM)

  # A clean, registered app with the widget's context, and the widget's installed root.
  def app
    @app ||= Dir.mktmpdir('app', DIR).tap do |dir|
      StageA::Context.register_pnpm(dir)
      StageA::Context.write(dir, GEM, self.class.root)
    end
  end

  # The same gem at another revision or source: a writable copy of its installed root, with its
  # manifest changed by the block, or unchanged without one.
  def upgraded
    dir = Dir.mktmpdir('upgraded', DIR)
    FileUtils.cp_r("#{self.class.root}/.", dir)
    FileUtils.chmod_R('u+w', dir)
    if block_given?
      manifest = JSON.parse(File.read("#{dir}/package.json"))
      yield manifest
      File.write("#{dir}/package.json", JSON.generate(manifest))
    end
    dir
  end

  it 'reports nothing for a clean app' do
    assert_empty StageA::Context.drift(app, { GEM => self.class.root })
  end

  it 'reports nothing when the gem changes revision or source but not its dependencies' do
    root = upgraded { it['version'] = '2.0.0' }

    assert_empty StageA::Context.drift(app, { GEM => root })
  end

  it 'reports a stale context when the gem changes its dependencies' do
    root = upgraded { it['dependencies']['ms'] = '2.1.3' }

    assert_equal ["#{GEM}: stale"], StageA::Context.drift(app, { GEM => root })
  end

  it 'reports a changed projection version' do
    assert_equal ["#{GEM}: projection changed from dependency-context-v1 to dependency-context-v2"],
                 StageA::Context.drift(app, { GEM => self.class.root },
                                       projection: 'dependency-context-v2')
  end

  it 'reports a missing registration' do
    File.write(File.join(app, 'pnpm-workspace.yaml'), "packages:\n  - apps/*\n")

    assert_equal ['registration missing'], StageA::Context.drift(app, { GEM => self.class.root })
  end

  it 'reports a participating gem with no context' do
    roots = { GEM => self.class.root, 'stage_a_widget_b' => upgraded }

    assert_includes StageA::Context.drift(app, roots), 'stage_a_widget_b: no context'
  end

  it 'reports a context whose gem no longer participates' do
    assert_equal ["#{GEM}: orphaned context"], StageA::Context.drift(app, {})
  end
end
