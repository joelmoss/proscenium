# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'json'

describe Proscenium::CLI::Inspect do
  it 'redacts credentials in URLs' do
    inspect = Proscenium::CLI::Inspect.new('/app', nil)

    # Assembled, so no credential-shaped URL sits in the source for scanners to flag.
    url = ['git+https://', 'user:fake', '@host/x.git#v1'].join

    assert_equal 'git+https://<redacted>@host/x.git#v1', inspect.send(:redact, url)
    assert_equal 'github:owner/repo#abc', inspect.send(:redact, 'github:owner/repo#abc')
  end

  # Bundler keeps a git source's query string, a token in it included.
  it 'redacts credentials in query strings' do
    inspect = Proscenium::CLI::Inspect.new('/app', nil)
    url = ['https://host/repo.git?ref=main&', 'access_token=fake1&API-KEY=fake2&sig=fake3'].join

    assert_equal 'https://host/repo.git?ref=main&access_token=<redacted>&API-KEY=<redacted>&' \
                 'sig=<redacted>', inspect.send(:redact, url)
  end

  # A context edited by hand, or only reformatted, is `edited`; one whose gem's dependencies
  # changed is `stale`.
  it 'tells a hand edit from a gem that changed' do
    dc = Proscenium::DependencyContext
    projected = ->(deps) { dc.to_json(dc.project('widget', 'dependencies' => deps)) }
    json = projected.call({ 'ms' => '^2' })
    context = Proscenium::CLI::Contexts::Context.new(gem: 'widget', json:)
    inspect = Proscenium::CLI::Inspect.new('/app', nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'package.json')
      status = lambda do |text|
        File.write(path, text)
        inspect.send(:status, context, text, path)
      end
      hand_edit = JSON.parse(context.json).merge('dependencies' => { 'ms' => '^3' })

      assert_equal 'edited', status.call(JSON.pretty_generate(hand_edit)), 'its hash left alone'
      assert_equal 'edited', status.call(JSON.generate(JSON.parse(context.json))), 'reformatted'
      assert_equal 'stale', status.call(projected.call({ 'ms' => '^1' })), 'the gem changed'
      assert_equal 'current', status.call(context.json)
    end
  end
end
