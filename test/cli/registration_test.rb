# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'proscenium/cli/registration'
require 'proscenium/cli/diff'
require 'yaml'

# Registering the contexts, spliced into the app's own files (#154, C06), and the diff install
# prints first.
describe Proscenium::CLI::Registration do
  R = Proscenium::CLI::Registration

  describe 'pnpm-workspace.yaml' do
    {
      '' => ['.proscenium/packages/*'],
      "minimumReleaseAge: 1440\n# keep\n" => ['.proscenium/packages/*'],
      "packages:\n  - apps/*\nfoo: 1\n" => ['.proscenium/packages/*', 'apps/*'],
      "packages: [\"apps/*\", libs/*] # mine\nfoo: 1\n" => ['apps/*', 'libs/*',
                                                            '.proscenium/packages/*'],
      "packages: []\n" => ['.proscenium/packages/*'],
      "packages: # list\n  - apps/*\n" => ['.proscenium/packages/*', 'apps/*']
    }.each do |text, packages|
      it "splices #{text.inspect}" do
        spliced = R.splice_pnpm_workspace(text)

        assert_equal packages, YAML.safe_load(spliced)['packages']
        assert_equal spliced, R.splice_pnpm_workspace(spliced)
        text.lines.reject { it.start_with?('packages') }.each { assert_includes spliced, it.chomp }
      end
    end
  end

  describe 'package.json' do
    {
      '' => %w[.proscenium/packages/*],
      "{\n  \"name\": \"app\"\n}\n" => %w[.proscenium/packages/*],
      '{"name":"app"}' => %w[.proscenium/packages/*],
      '{}' => %w[.proscenium/packages/*],
      "{\n  \"workspaces\": [\n    \"apps/*\"\n  ],\n  \"name\": \"app\"\n}\n" =>
        %w[apps/* .proscenium/packages/*],
      '{"workspaces": ["apps/*"], "name": "app"}' => %w[apps/* .proscenium/packages/*],
      '{"workspaces": []}' => %w[.proscenium/packages/*],
      "{\n  \"workspaces\": {\n    \"packages\": [\"apps/*\"],\n    \"nohoist\": []\n  }\n}\n" =>
        %w[apps/* .proscenium/packages/*]
    }.each do |text, workspaces|
      it "splices #{text.inspect}" do
        spliced = R.splice_package_json(text)
        json = JSON.parse(spliced)
        actual = json['workspaces']
        actual = actual['packages'] if actual.is_a?(Hash)

        assert_equal workspaces, actual
        assert_equal spliced, R.splice_package_json(spliced)
        assert_equal JSON.parse(text.empty? ? '{}' : text).except('workspaces'),
                     json.except('workspaces')
      end
    end

    it 'keeps the indentation of the file' do
      assert_equal <<~JSON, R.splice_package_json(<<~ORIGINAL)
        {
            "workspaces": [".proscenium/packages/*"],
            "name": "app"
        }
      JSON
        {
            "name": "app"
        }
      ORIGINAL
    end
  end

  describe '.gitignore' do
    it 'adds the lines it owns and a node_modules rule only if missing' do
      assert_equal "/node_modules\n\n# Proscenium\n.proscenium/*\n!.proscenium/packages/\n" \
                   ".proscenium/packages/*/node_modules/\n",
                   R.splice_gitignore("/node_modules\n")
      assert_equal "# Proscenium\nnode_modules/\n.proscenium/*\n!.proscenium/packages/\n" \
                   ".proscenium/packages/*/node_modules/\n", R.splice_gitignore('')
      done = R.splice_gitignore("x\n")

      assert_equal done, R.splice_gitignore(done)
    end
  end

  it 'lists the edits a project needs, and none once registered' do
    Dir.mktmpdir do |root|
      File.write(File.join(root, 'pnpm-workspace.yaml'), "minimumReleaseAge: 1440\n")
      File.write(File.join(root, '.gitignore'), "node_modules/\n")
      edits = R.edits(root, 'pnpm')

      assert_equal(%w[pnpm-workspace.yaml .gitignore], edits.map { File.basename(it[0]) })
      refute R.registered?(root, 'pnpm')
      edits.each { |path, _, text| File.write(path, text) }

      assert_empty R.edits(root, 'pnpm')
      assert R.registered?(root, 'pnpm')
    end
  end

  it 'prints an edit as a unified diff' do
    before = "packages:\n  - apps/*\n"
    after = R.splice_pnpm_workspace(before)

    assert_equal <<~DIFF, Proscenium::CLI::Diff.unified('pnpm-workspace.yaml', before, after)
      --- pnpm-workspace.yaml
      +++ pnpm-workspace.yaml
      @@ -1,2 +1,3 @@
       packages:
      +  - .proscenium/packages/*
         - apps/*
    DIFF
  end

  it 'diffs a new file from nothing' do
    assert_equal "--- .gitignore\n+++ .gitignore\n@@ -0,0 +1,1 @@\n+x\n",
                 Proscenium::CLI::Diff.unified('.gitignore', '', "x\n")
  end
end
