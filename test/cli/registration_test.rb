# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'proscenium/cli/registration'
require 'proscenium/cli/pnpm_workspace'
require 'proscenium/cli/collisions'
require 'proscenium/cli/diff'
require 'yaml'
require 'json'

# Registering the contexts, spliced into the app's own files (#154, C06), and the diff install
# prints first.
describe Proscenium::CLI::Registration do
  R = Proscenium::CLI::Registration
  P = Proscenium::CLI::PnpmWorkspace
  G = Proscenium::CLI::Gitignore

  # What pnpm reads: anchors and dates are valid YAML.
  def load_yaml(text) = YAML.safe_load(text, aliases: true, permitted_classes: [Date, Time])

  describe 'pnpm-workspace.yaml' do
    # A list inherited through a merge key would be overridden by a new one, dropping the app's
    # workspaces; nothing short of rewriting the file keeps it.
    # Adding to an anchored list would add to every alias of it as well.
    it 'refuses an anchored list another key aliases' do
      error = assert_raises(Proscenium::CLI::Error) { P.splice("packages: &p [a]\nother: *p\n") }

      assert_equal 'PSM-E-REGISTRATION', error.code
    end

    # pnpm applies an exclusion whatever its order, so a `!` pattern covering a context means it
    # is never installed: registering would change nothing.
    it 'refuses a packages list that excludes the contexts' do
      ["packages:\n  - .proscenium/packages/*\n  - '!.proscenium/packages/*'\n",
       "packages: ['!.proscenium/packages/hue']\n", "packages: ['!**']\n",
       "packages: ['.proscenium/packages/*', '!.proscenium/packages/[ah]ue']\n"].each do |text|
        error = assert_raises(Proscenium::CLI::Error, text) { P.splice(text) }

        assert_equal 'PSM-E-REGISTRATION-EXCLUDED', error.code
      end
      assert_equal ['!apps/legacy', 'apps/*', '.proscenium/packages/*'],
                   load_yaml(P.splice("packages: ['!apps/legacy', 'apps/*']\n"))['packages']
      error = assert_raises(Proscenium::CLI::Error) do
        R.splice_package_json('{"workspaces": ["!.proscenium/packages/*"]}')
      end

      assert_equal 'PSM-E-REGISTRATION-EXCLUDED', error.code
    end

    it 'refuses packages inherited through a merge key' do
      text = "defaults: &d\n  packages: [apps/*]\n<<: *d\n"
      error = assert_raises(Proscenium::CLI::Error) { P.splice(text) }

      assert_equal 'PSM-E-REGISTRATION', error.code
    end

    {
      '' => ['.proscenium/packages/*'],
      "minimumReleaseAge: 1440\n# keep\n" => ['.proscenium/packages/*'],
      "packages:\n  - apps/*\nfoo: 1\n" => ['.proscenium/packages/*', 'apps/*'],
      "packages: [\"apps/*\", libs/*] # mine\nfoo: 1\n" => ['apps/*', 'libs/*',
                                                            '.proscenium/packages/*'],
      "packages: []\n" => ['.proscenium/packages/*'],
      "packages: # list\n  - apps/*\n" => ['.proscenium/packages/*', 'apps/*'],
      # Items at the key's own column, or deeper than two spaces, are both valid YAML.
      "packages:\n- packages/*\n- apps/*\n" => ['.proscenium/packages/*', 'packages/*', 'apps/*'],
      "packages:\n    - packages/*\n" => ['.proscenium/packages/*', 'packages/*'],
      # A commented-out pattern does not register the contexts.
      "packages:\n  - app\n# - .proscenium/packages/*\n" => ['.proscenium/packages/*', 'app'],
      # Valid YAML that a plain safe_load refuses: a date, and an anchor with its alias.
      "released: 2026-01-01\npackages:\n  - apps/*\n" => ['.proscenium/packages/*', 'apps/*'],
      "base: &b 1\nother: *b\npackages:\n  - apps/*\n" => ['.proscenium/packages/*', 'apps/*'],
      "# only a comment\n" => ['.proscenium/packages/*'],
      # "packages:" earlier in the file, in a comment or a key, is not the key.
      "# Workspace packages:\npackages:\n  - a\n" => ['.proscenium/packages/*', 'a'],
      "catalogs:\n  my-packages:\n    x: 1\npackages:\n  - a\n" => ['.proscenium/packages/*', 'a'],
      "packages: [a, b,]\n" => ['a', 'b', '.proscenium/packages/*'],
      # Space before the colon is valid YAML, and pnpm reads it.
      "packages : [\"apps/*\"]\n" => ['apps/*', '.proscenium/packages/*'],
      "packages :\n  - apps/*\n" => ['.proscenium/packages/*', 'apps/*'],
      # A quoted key is the same key.
      "\"packages\":\n  - a\n" => ['.proscenium/packages/*', 'a'],
      "'packages': [a]\n" => ['a', '.proscenium/packages/*'],
      # Nor does one in a comment, which may follow a flow delimiter directly.
      "packages: [\"a\", # close ] later\n  b,\n]\n" => ['a', 'b', '.proscenium/packages/*'],
      "packages: [a,# close ] later\n  b,\n]\n" => ['a', 'b', '.proscenium/packages/*'],
      # A bracket inside a quoted glob does not end the list.
      "packages: ['packages/[ab]', \"x]\"]\n" => ['packages/[ab]', 'x]', '.proscenium/packages/*'],
      # Entries pnpm reads, whatever their type.
      "packages:\n  - a\n  -\n" => ['.proscenium/packages/*', 'a', nil],
      # A root mapping indented as a whole, which pnpm reads too.
      "  packages:\n    - app/*\n  foo: 1\n" => ['.proscenium/packages/*', 'app/*'],
      "  foo: 1\n  packages: [app/*]\n" => ['app/*', '.proscenium/packages/*'],
      # Another mapping's `packages` key is not the root's.
      "catalog:\n  packages: [x]\npackages:\n  - a\n" => ['.proscenium/packages/*', 'a'],
      # An anchored list is the list; the anchor stays where it is.
      "packages: &p [a]\n" => ['a', '.proscenium/packages/*'],
      "packages: &p # mine\n  - a\n" => ['.proscenium/packages/*', 'a'],
      # A list reached through an alias is spelled out, leaving the anchored one as it is.
      "base: &p [packages/*, \"it's\"]\npackages: *p\n" => ['packages/*', "it's",
                                                            '.proscenium/packages/*']
    }.each do |text, packages|
      it "splices #{text.inspect}" do
        spliced = P.splice(text)

        assert_equal packages, load_yaml(spliced)['packages']
        assert_equal spliced, P.splice(spliced)
        text.lines.grep_v(/\A\s*['"]?packages/).each { assert_includes spliced, it.chomp }
      end
    end
  end

  it 'keeps a CRLF file in CRLF' do
    both = %w[.proscenium/packages/* apps/*]
    ["packages:\r\n  - apps/*\r\n", "packages: ['apps/*']\r\nfoo: 1\r\n",
     "packages: [\r\n  'apps/*'\r\n]\r\n"].each do |text|
      spliced = P.splice(text)

      assert_equal both.sort, load_yaml(spliced)['packages'].sort
      refute_match(/(?<!\r)\n/, spliced)
    end
    ["{\r\n  \"name\": \"app\"\r\n}\r\n", "{\r\n  \"workspaces\": [\r\n    \"a\"\r\n  ]\r\n}\r\n",
     "x\r\n"].each do |text|
      spliced = text.start_with?('{') ? R.splice_package_json(text) : G.splice(text)

      refute_match(/(?<!\r)\n/, spliced)
    end
  end

  it 'keeps a multi-line flow list on its lines, and its trailing comma' do
    assert_equal "packages: [\n  'apps/*',\n  '.proscenium/packages/*'\n]\n",
                 P.splice("packages: [\n  'apps/*'\n]\n")
    assert_equal "packages: [\n  'apps/*',\n  '.proscenium/packages/*',\n]\n",
                 P.splice("packages: [\n  'apps/*',\n]\n")
  end

  # An aliased list as a mapping key costs Ruby exponential work to hash once built, so the file
  # is read from its parse tree: the engine reads it on every generation.
  it 'reads a file with an aliased mapping key at once' do
    text = +"a: &a [x, x]\n"
    ('a'..'z').each_cons(2) { |from, to| text << "#{to}: &#{to} [*#{from}, *#{from}]\n" }
    text << "? *z\n: 1\npackages:\n  - apps/*\n"
    thread = Thread.new do
      [Proscenium::ContextMap.registered_in?('pnpm-workspace.yaml', text), P.splice(text)]
    end

    assert thread.join(2), 'reading it did not finish in 2 seconds'
    registered, spliced = thread.value

    refute registered
    assert_includes spliced, "  - .proscenium/packages/*\n  - apps/*\n"
  ensure
    thread&.kill
  end

  # The engine counts a file it cannot parse that names the pattern, so as not to switch off; the
  # CLI must not, or it would skip registering a file its manager will reject.
  it 'registers only a file it can parse, whatever the pattern appears in' do
    ["packages: [a\n# .proscenium/packages/*\n",
     "packages: {a\n# .proscenium/packages/*\n"].each do |text|
      assert_equal('PSM-E-REGISTRATION',
                   assert_raises(Proscenium::CLI::Error) { P.splice(text) }.code, text)
    end
    error = assert_raises(Proscenium::CLI::Error) do
      R.splice_package_json('{"description": ".proscenium/packages/*", ')
    end

    assert_equal 'PSM-E-REGISTRATION', error.code
  end

  it 'keeps a byte order mark' do
    spliced = P.splice("\uFEFFpackages:\n  - apps/*\n")

    assert_equal "\uFEFFpackages:\n  - .proscenium/packages/*\n  - apps/*\n", spliced
  end

  # Aliases are valid YAML, and are compared unexpanded: expanding one that nests nine deep would
  # never finish.
  it 'splices a file whose aliases expand enormously, at once' do
    text = "packages: [x]\na: &a [#{Array.new(9, '1').join(', ')}]\n"
    ('a'..'i').each_cons(2) do |from, to|
      text << "#{to}: &#{to} [#{Array.new(9, "*#{from}").join(', ')}]\n"
    end
    thread = Thread.new { P.splice(text) }

    assert thread.join(2), 'splice did not finish in 2 seconds'
    assert_includes thread.value, "'.proscenium/packages/*'"
  ensure
    thread&.kill
  end

  it 'refuses a pnpm-workspace.yaml it cannot parse, rather than write one pnpm cannot' do
    error = assert_raises(Proscenium::CLI::Error) { P.splice("packages: [apps/*\n") }

    assert_equal 'PSM-E-REGISTRATION', error.code
  end

  # Each parses, but the splice would not add the pattern to the list pnpm reads; the result is
  # checked, and refused rather than written.
  ["packages: ~\nfoo: 1\n", "packages: apps/*\n", "- a\n"].each do |text|
    it "refuses #{text.inspect} rather than write it wrongly" do
      error = assert_raises(Proscenium::CLI::Error) { P.splice(text) }

      assert_equal 'PSM-E-REGISTRATION', error.code
    end
  end

  it 'counts only a registration the file actually lists' do
    Dir.mktmpdir do |root|
      File.write(File.join(root, 'pnpm-workspace.yaml'),
                 "packages:\n  - app\n# - .proscenium/packages/*\n")

      refute R.registered?(root, 'pnpm')
    end
  end

  # The engine's adoption test: a registered file it cannot parse still counts, so a parse failure
  # never silently switches off the context map and the stale check.
  it 'counts a registration in valid YAML safe_load refuses, or in a file it cannot parse' do
    Dir.mktmpdir do |root|
      ["when: 2026-01-01\npackages:\n  - .proscenium/packages/*\n",
       "a: &a 1\nb: *a\npackages:\n  - .proscenium/packages/*\n",
       "packages: [.proscenium/packages/*\n"].each do |text|
        File.write(File.join(root, 'pnpm-workspace.yaml'), text)

        assert R.registered?(root, 'pnpm'), "not registered: #{text.inspect}"
      end
      File.write(File.join(root, 'package.json'),
                 "\uFEFF{\"workspaces\": [\".proscenium/packages/*\"]}")

      assert R.registered?(root, 'bun')
    end
  end

  # Each parses only with the BOM stripped, or with dates and aliases allowed, and names the
  # pattern outside the list: a parse that fell back to the text would count it.
  it 'does not count the pattern outside the list, in a file that needs a lenient parse' do
    {
      'pnpm-workspace.yaml' => ["\uFEFFfoo: .proscenium/packages/*\n",
                                "when: 2026-01-01\npackages:\n  - a\n# .proscenium/packages/*\n",
                                "a: &a 1\nb: *a\npackages:\n  - a\n# .proscenium/packages/*\n"],
      'package.json' => ["\uFEFF{\"description\": \".proscenium/packages/*\"}"]
    }.each do |file, texts|
      texts.each { refute Proscenium::ContextMap.registered_in?(file, it), it }
    end
  end

  it 'counts the forms pnpm and Bun read as the pattern, and a file it cannot parse' do
    map = Proscenium::ContextMap

    assert map.registered_in?('pnpm-workspace.yaml', "packages:\n  - ./.proscenium/packages/*\n")
    assert map.registered_in?('package.json', '{"workspaces": [".proscenium/packages/*/"]}')
    assert map.registered_in?('package.json', '{"workspaces": [".proscenium/packages/*", }')
    assert map.registered_in?('pnpm-workspace.yaml',
                              "a: !!float foo\npackages:\n  - .proscenium/packages/*\n")
    # Any caller's encoding: under LANG=C, Ruby tags what it reads as US-ASCII.
    text = "# caf\u00e9\npackages:\n  - .proscenium/packages/*\n".b.force_encoding('US-ASCII')

    assert map.registered_in?('pnpm-workspace.yaml', text)
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
        %w[apps/* .proscenium/packages/*],
      '{"workspaces": {"catalog": {"react": "18.3.1"}, "packages": ["apps/*"]}}' =>
        %w[apps/* .proscenium/packages/*],
      # Another object's `workspaces` or `packages` key, before the root's, is not the root's.
      '{"tool": {"workspaces": []}, "workspaces": ["app/*"]}' => %w[app/* .proscenium/packages/*],
      '{"workspaces": {"catalog": {"packages": ["x"]}, "packages": ["apps/*"]}}' =>
        %w[apps/* .proscenium/packages/*],
      '{"workspaces": ["packages/[ab]", "x\\"]"]}' =>
        ['packages/[ab]', 'x"]', '.proscenium/packages/*']
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

    # A workspaces value with no packages list to append to: refused, never a second
    # "workspaces" key.
    ['{"workspaces": {"nohoist": ["x"]}, "name": "app"}', '{"workspaces": "apps/*"}', '[]',
     '{nope'].each do |text|
      it "refuses #{text}" do
        error = assert_raises(Proscenium::CLI::Error) { R.splice_package_json(text) }

        assert_equal 'PSM-E-REGISTRATION', error.code
      end
    end

    it 'keeps a byte order mark' do
      spliced = R.splice_package_json("\uFEFF{\"name\": \"app\"}")

      assert spliced.start_with?("\uFEFF{")
      json = JSON.parse(spliced.delete_prefix("\uFEFF"))

      assert_equal %w[.proscenium/packages/*], json['workspaces']
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
      owned = "!.proscenium/\n.proscenium/*\n!.proscenium/packages/\n!.proscenium/packages/*/\n" \
              "!.proscenium/packages/*/package.json\n.proscenium/packages/*/node_modules/\n"

      assert_equal "/node_modules\n\n# Proscenium\n#{owned}", G.splice("/node_modules\n")
      assert_equal "# Proscenium\nnode_modules/\n#{owned}", G.splice('')
      done = G.splice("x\n")

      assert_equal done, G.splice(done)
    end

    # Its own lines out of order are no better than another rule: `.proscenium/*` after the
    # negations hides the contexts again.
    it 'adds the lines again in order when the ones there are reordered' do
      Dir.mktmpdir('ignore') do |dir|
        system('git', 'init', '-q', dir, exception: true)
        lines = G::IGNORES.partition { it.start_with?('!') }.flatten
        reordered = G.splice("node_modules/\n#{lines.join("\n")}\n")
        File.write(File.join(dir, '.gitignore'), reordered)

        refute system('git', '-C', dir, 'check-ignore', '-q', '--no-index',
                      '.proscenium/packages/hue/package.json')
        assert_equal reordered, G.splice(reordered)
      end
    end

    # Git applies the last matching rule, so a later one naming a gem's own directory hides that
    # gem's context: the lines go after it again.
    it 'adds the lines again after a later rule that names a gem' do
      %w[.proscenium/packages/hue/** hue/ .proscenium/packages/hue/package.json
         .proscenium/packages/[ah]ue/** .proscenium/packages/h?e/ **/{hue,ui}/].each do |rule|
        Dir.mktmpdir('ignore') do |dir|
          system('git', 'init', '-q', dir, exception: true)
          text = "#{G.splice('')}#{rule}\n"
          File.write(File.join(dir, '.gitignore'), G.splice(text))

          refute_equal text, G.splice(text), rule
          refute system('git', '-C', dir, 'check-ignore', '-q', '--no-index',
                        '.proscenium/packages/hue/package.json'), rule
        end
      end
    end

    # Git does not look inside an ignored directory, so an earlier rule ignoring .proscenium/
    # itself, or everything under it, would hide every context unless each level is re-included.
    it 'keeps the contexts committable under a rule that ignores .proscenium/' do
      ['.proscenium/', '.*', '.proscenium/**', '**/.proscenium/**',
       '.proscenium/**/packages/*/package.json'].each do |rule|
        Dir.mktmpdir('ignore') do |dir|
          system('git', 'init', '-q', dir, exception: true)
          # The rule before the lines, after them, and between a negation and a later line.
          before = G.splice("#{rule}\n")
          after = G.splice("#{G.splice('')}#{rule}\n")
          between = G.splice("!.proscenium/packages/*/package.json\n#{rule}\n" \
                             ".proscenium/packages/*/node_modules/\n")
          File.write(File.join(dir, '.gitignore'), before)
          ignored = lambda do |path|
            system('git', '-C', dir, 'check-ignore', '-q', '--no-index', path)
          end

          refute ignored.call('.proscenium/packages/hue/package.json'), "under #{rule}"
          assert ignored.call('.proscenium/lock'), "under #{rule}"
          assert ignored.call('.proscenium/packages/hue/node_modules/x/a.js'), "under #{rule}"
          File.write(File.join(dir, '.gitignore'), after)

          refute ignored.call('.proscenium/packages/hue/package.json'), "then #{rule}"
          assert_equal after, G.splice(after)
          File.write(File.join(dir, '.gitignore'), between)

          refute ignored.call('.proscenium/packages/hue/package.json'), "between #{rule}"
          assert_equal between, G.splice(between)
        end
      end
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

  # Writing through a link could edit a file outside the app, so a file install would change is
  # refused as one, before anything is written; one it would leave alone is fine.
  it 'refuses to edit a registration file that is a link' do
    Dir.mktmpdir do |root|
      outside = File.join(root, 'outside')
      File.write(outside, "node_modules/\n")
      begin
        File.symlink(outside, File.join(root, '.gitignore'))
      rescue NotImplementedError, Errno::EPERM, Errno::EACCES
        skip 'symlinks need privileges here'
      end
      File.write(File.join(root, 'pnpm-workspace.yaml'), "packages:\n  - .proscenium/packages/*\n")
      error = assert_raises(Proscenium::CLI::Error) { R.edits(root, 'pnpm') }

      assert_equal ['PSM-E-OWNED-LINK', '.gitignore'], [error.code, error.message[/\A\S+/]]
      assert_equal "node_modules/\n", File.read(outside)
      File.write(outside, G.splice("node_modules/\n"))

      assert_empty R.edits(root, 'pnpm')
    end
  end

  # C05: the app's own packages are left alone, and one taking a context's name is refused.
  describe 'collisions' do
    before { @root = Dir.mktmpdir('collisions') }
    after { FileUtils.rm_rf(@root) }

    def write(path, body)
      FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
      File.write(File.join(@root, path), body)
    end

    it 'names a dependency on a gem that is not its context, as a pin from before adopting' do
      write('package.json', JSON.generate(
                              'dependencies' => { '@rubygems/hue' => 'github:harleytherapy/hue#1',
                                                  '@rubygems/other' => '1.0.0', 'react' => '18' },
                              'devDependencies' => { '@rubygems/widget' => 'workspace:*' },
                              'optionalDependencies' => {
                                '@rubygems/hue' => 'link:.proscenium/packages/hue'
                              }
                            ))

      assert_equal ['package.json dependencies has @rubygems/hue as "github:harleytherapy/hue#1"'],
                   Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue widget])
    end

    # Only a link to the gem's own context is the context; one to a vendored copy is another source.
    it 'names a link to anything but the context' do
      deps = { '@rubygems/hue' => 'link:vendor/hue',
               '@rubygems/widget' => 'link:./.proscenium/packages/widget/' }
      write('package.json', JSON.generate('dependencies' => deps))

      assert_equal ['package.json dependencies has @rubygems/hue as "link:vendor/hue"'],
                   Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue widget])
    end

    # `workspace:<name>@<range>` is another workspace package under the context's name.
    it 'names a workspace alias to another package' do
      deps = { '@rubygems/hue' => 'workspace:other@*', '@rubygems/widget' => 'workspace:^1.0.0',
               '@rubygems/ui' => 'workspace:@rubygems/ui@*' }
      write('package.json', JSON.generate('dependencies' => deps))

      assert_equal ['package.json dependencies has @rubygems/hue as "workspace:other@*"'],
                   Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue widget ui])
    end

    it 'names a workspace package with a context name, skipping excluded ones' do
      write('pnpm-workspace.yaml', "packages:\n  - packages/*\n  - '!packages/old'\n  " \
                                   "- .proscenium/packages/*\n")
      write('packages/hue/package.json', '{"name": "@rubygems/hue"}')
      write('packages/old/package.json', '{"name": "@rubygems/widget"}')
      write('packages/ui/package.json', '{"name": "ui"}')
      write('.proscenium/packages/hue/package.json', '{"name": "@rubygems/hue"}')

      assert_equal ['packages/hue/package.json is named @rubygems/hue'],
                   Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue widget])
      # An exclusion with braces, which pnpm expands, or spelled with or without a leading `./`.
      ["  - packages/*\n  - '!packages/{hue,old}'\n", "  - ./packages/*\n  - '!packages/hue'\n",
       "  - packages/*\n  - '!./packages/hue'\n"].each do |list|
        write('pnpm-workspace.yaml', "packages:\n#{list}")

        assert_empty Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue]), list
      end
    end

    it 'reads a pnpm-workspace.yaml with dates and aliases, and skips one it cannot parse' do
      write('pnpm-workspace.yaml', "when: 2026-01-01\nbase: &b packages/*\npackages:\n  - *b\n")
      write('packages/hue/package.json', '{"name": "@rubygems/hue"}')

      assert_equal ['packages/hue/package.json is named @rubygems/hue'],
                   Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue])
      write('pnpm-workspace.yaml', "packages: [packages/*\n")

      assert_empty Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue])
    end

    it 'skips the contexts however the registration spells them' do
      %w[./.proscenium/packages/* .proscenium/packages/*/].each do |pattern|
        write('pnpm-workspace.yaml', "packages:\n  - '#{pattern}'\n")
        write('.proscenium/packages/hue/package.json', '{"name": "@rubygems/hue"}')

        assert_empty Proscenium::CLI::Collisions.find(@root, 'pnpm', %w[hue]), pattern
      end
    end

    it "reads Bun's workspaces from package.json" do
      write('package.json', '{"workspaces": {"packages": ["libs/*", ".proscenium/packages/*"]}}')
      write('libs/hue/package.json', '{"name": "@rubygems/hue"}')

      assert_equal ['libs/hue/package.json is named @rubygems/hue'],
                   Proscenium::CLI::Collisions.find(@root, 'bun', %w[hue])
      assert_empty Proscenium::CLI::Collisions.find(@root, 'bun', %w[widget])
    end
  end

  # C48: a Bun app that sets no linker gets the one it uses today, in the registration diff.
  describe 'the Bun linker' do
    # Bun reads the user's settings too, so the developer's own ~/.npmrc stays out of it.
    before do
      @root = Dir.mktmpdir('linker')
      @home = Dir.mktmpdir('home')
      @env = ENV.to_h.slice('HOME', 'XDG_CONFIG_HOME')
      ENV['HOME'] = @home
      ENV.delete('XDG_CONFIG_HOME')
    end

    after do
      ENV.delete('XDG_CONFIG_HOME')
      @env.each { |key, value| ENV[key] = value }
      FileUtils.rm_rf([@root, @home])
    end

    def write(path, body)
      FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
      File.write(File.join(@root, path), body)
    end

    def linker = Proscenium::CLI::BunLinker.current(@root)

    it 'sets the linker in a CRLF [install] table, in CRLF' do
      text = "[install]\r\nexact = true\r\n"
      spliced = Proscenium::CLI::BunLinker.splice(text, 'hoisted')

      assert_equal "[install]\r\nlinker = \"hoisted\"\r\nexact = true\r\n", spliced
      write('bunfig.toml', spliced)

      assert_equal 'hoisted', Proscenium::CLI::Manager.new('bun', @root).bun_linker
    end

    it 'keeps the layout already installed' do
      FileUtils.mkdir_p(File.join(@root, 'node_modules/react'))

      assert_equal 'hoisted', linker
      FileUtils.mkdir_p(File.join(@root, 'node_modules/.bun'))

      assert_equal 'isolated', linker
    end

    it 'takes what Bun would pick with nothing installed yet' do
      write('package.json', '{"name": "app"}')

      assert_equal 'hoisted', linker
      write('package.json', '{"workspaces": ["packages/*"]}')
      write('bun.lock', '{"lockfileVersion": 1, "configVersion": 1}')

      assert_equal 'isolated', linker
      write('bun.lock', '{"lockfileVersion": 1}')

      assert_equal 'hoisted', linker
    end

    # Bun 1.4 takes node-linker from .npmrc (probed on 1.4.2), so an app that chose one there keeps
    # it, whatever is installed today.
    it "takes .npmrc's node-linker first" do
      write('.npmrc', "registry=https://registry.npmjs.org/\nnode-linker = isolated\n")

      assert_equal 'isolated', linker
      FileUtils.mkdir_p(File.join(@root, 'node_modules/react'))

      assert_equal 'isolated', linker
      write('.npmrc', "node-linker=hoisted\n")
      write('package.json', '{"workspaces": ["packages/*"]}')
      write('bun.lock', '{"lockfileVersion": 1, "configVersion": 1}')
      FileUtils.rm_rf(File.join(@root, 'node_modules'))

      assert_equal 'hoisted', linker
      write('.npmrc', "; node-linker=hoisted\nnode-linker=pnp\n")

      assert_equal 'isolated', linker, 'a comment, or a linker Bun does not have, is not a choice'
    end

    # Every spelling Bun 1.4.2 reads (probed): node-linker's pnpm and npm, and install-strategy,
    # which node-linker overrides wherever it sits in the file.
    it "reads each of .npmrc's linker spellings" do
      { "node-linker=pnpm\n" => 'isolated', "node-linker=npm\n" => 'hoisted',
        "install-strategy=linked\n" => 'isolated', "install-strategy=nested\n" => 'hoisted',
        "node-linker=hoisted\ninstall-strategy=linked\n" => 'hoisted',
        "install-strategy=hoisted\nnode-linker=isolated\n" => 'isolated',
        "node-linker = \"isolated\"\n" => 'isolated' }.each do |npmrc, expected|
        write('.npmrc', npmrc)

        assert_equal expected, linker, npmrc
      end
    end

    # The linker goes into the committed bunfig.toml, so only the project decides it: a
    # developer's own ~/.npmrc, $XDG_CONFIG_HOME/.npmrc or global .bunfig.toml, which Bun also
    # reads, would make one person's preference the whole team's.
    it "ignores the developer's own Bun and npm config" do
      xdg = File.join(@home, 'xdg')
      FileUtils.mkdir_p(xdg)
      ENV['XDG_CONFIG_HOME'] = xdg
      [File.join(@home, '.npmrc'), File.join(xdg, '.npmrc')].each do |path|
        File.write(path, "node-linker=isolated\n")
      end
      [File.join(@home, '.bunfig.toml'), File.join(xdg, '.bunfig.toml')].each do |path|
        File.write(path, "[install]\nlinker = \"isolated\"\n")
      end
      write('package.json', '{"name": "app"}')

      assert_equal 'hoisted', linker, "Bun's default for the app as it stands"
      write('.npmrc', "node-linker=isolated\n")

      assert_equal 'isolated', linker, "the project's own .npmrc"
    end

    it 'splices it into bunfig.toml, keeping what is there' do
      splice = ->(text) { Proscenium::CLI::BunLinker.splice(text, 'hoisted') }

      assert_equal "[install]\nlinker = \"hoisted\"\n", splice.call('')
      assert_equal "[test]\nx = 1\n\n[install]\nlinker = \"hoisted\"\n",
                   splice.call("[test]\nx = 1\n")
      assert_equal "[install] # mine\nlinker = \"hoisted\"\nexact = true\n",
                   splice.call("[install] # mine\nexact = true\n")
      assert_equal "[\"install\"]\nlinker = \"hoisted\"\nexact = true\n",
                   splice.call("[\"install\"]\nexact = true\n")
    end

    it 'is one of the registration edits only when no linker is set' do
      write('package.json', '{"name": "app", "trustedDependencies": []}')
      FileUtils.mkdir_p(File.join(@root, 'node_modules/react'))

      assert_includes R.edits(@root, 'bun').map { File.basename(it[0]) }, 'bunfig.toml'
      write('bunfig.toml', "[install]\nlinker = \"isolated\"\n")

      refute_includes R.edits(@root, 'bun').map { File.basename(it[0]) }, 'bunfig.toml'
    end
  end

  it 'prints an edit as a unified diff' do
    before = "packages:\n  - apps/*\n"
    after = P.splice(before)

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
