# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'json'
require 'proscenium/contexts/stale'

# The engine, `install --frozen` and `inspect` each say why a committed context differs from the
# one install would write. They classify it alike, from Contexts::Stale, so the frozen drift list
# names the cause the engine's build error names.
describe 'classifying a committed dependency context' do
  dc = Proscenium::Contexts::Projection
  projected = ->(deps) { dc.to_json(dc.project('widget', 'dependencies' => deps)) }
  current = JSON.parse(projected.call({ 'ms' => '^2' }))
  changed = JSON.parse(projected.call({ 'ms' => '^1' }))
  edited = 'its dependency context was edited by hand'
  version = 'its dependency context was written by a different version of Proscenium'
  stale = 'its NPM dependencies changed since its dependency context was written'
  other_version = current['proscenium'].merge('projection' => 'dependency-context-v0')
  hash_edit = current['proscenium'].merge('projectionSha256' => '0' * 64)

  # [committed file, engine's reason (nil: it builds), frozen's reason, inspect's status]. Only
  # contexts install would own: one that is not valid JSON, or not generated, is refused before
  # the drift check (`check_owned_directory`), and the engine's wording for it is pinned in
  # stale_contexts_test.rb.
  {
    'reformatted' => [JSON.generate(current), nil, edited, 'edited'],
    'a field edited, its hash kept' =>
      [JSON.pretty_generate(current.merge('dependencies' => { 'ms' => '^3' })), edited, edited,
       'edited'],
    'only its hash edited' =>
      [JSON.pretty_generate(current.merge('proscenium' => hash_edit)), edited, edited, 'edited'],
    'a field edited after the gem changed' =>
      [JSON.pretty_generate(changed.merge('description' => 'mine')), edited, edited, 'edited'],
    'the gem changed' => [JSON.pretty_generate(changed), stale, stale, 'stale'],
    'written by another version' =>
      [JSON.pretty_generate(current.merge('proscenium' => other_version)), version, version,
       'stale']
  }.each do |name, (text, engine, frozen, status)|
    it "agrees on a context #{name}" do
      context = Proscenium::Contexts::Plan::Context.new(gem: 'widget', json: dc.to_json(current))
      Dir.mktmpdir do |root|
        path = File.join(root, 'package.json')
        File.write(path, text)
        install = Proscenium::CLI::Install.allocate
        install.instance_variable_set(:@root, root)
        install.instance_variable_set(:@committed, { 'widget' => path })
        cause, *diff = install.send(:describe_change, context).lines

        reason = Proscenium::Contexts::Stale.compare(context, path)
        engine ? assert_equal(engine, reason, 'engine') : assert_nil(reason, 'engine builds it')
        assert_equal "widget: #{frozen}", cause.chomp, 'install --frozen'
        refute_empty diff, 'install --frozen shows the diff'
        inspect = Proscenium::CLI::Inspect.new(root, nil)

        assert_equal status, inspect.send(:status, context, text, path), 'inspect'
      end
    end
  end

  # Value: protects=a context that was never written naming its cause, with no diff to show;
  # fails_when=describe_change reads a file that is not there, or drift stops returning :missing;
  # why_new=the rows above all write a file, and install_test.rb's check needs STAGE_A; seam=none;
  # no_claim=says nothing of a context that is not valid JSON, which install refuses earlier
  it 'agrees on a context that has not been written' do
    context = Proscenium::Contexts::Plan::Context.new(gem: 'widget', json: dc.to_json(current))
    Dir.mktmpdir do |root|
      path = File.join(root, 'package.json')
      install = Proscenium::CLI::Install.allocate
      install.instance_variable_set(:@root, root)
      install.instance_variable_set(:@committed, {})
      missing = "its dependency context hasn't been written yet"

      assert_equal missing, Proscenium::Contexts::Stale.compare(context, path)
      assert_equal missing, Proscenium::Contexts::Stale.compare(context, nil)
      assert_equal "widget: #{missing}", install.send(:describe_change, context)
    end
  end
end
