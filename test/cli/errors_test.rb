# frozen_string_literal: true

require_relative 'helper'

# Golden output for every error code: the human text and the JSON event, pinned in
# test/cli/golden/. Run with GOLDEN=update to rewrite them after a deliberate change.
describe Proscenium::CLI::Error do
  GOLDEN = File.expand_path('golden', __dir__)

  # Arguments that render each code. A new code needs an entry here, which gives it a golden.
  EXAMPLES = {
    'PSM-E-USAGE' => { detail: 'Unknown command: frobnicate' },
    'PSM-E-INTERNAL' => { detail: 'ArgumentError: boom' },
    'PSM-E-GEMSPEC' => { path: '/src/widget', found: 0 },
    'PSM-E-NOT-OPTED-IN' => { gem: 'widget' },
    'PSM-E-FRONTEND-ROOT' => { gem: 'widget', root: '../outside' },
    'PSM-E-MANIFEST' => { gem: 'widget', path: 'package.json', cause: 'it is missing' },
    'PSM-E-GEM-FILES' => { gem: 'widget', files: 'package.json' },
    'PSM-E-NAME' => { gem: 'Widget' },
    'PSM-E-WORKSPACES' => { gem: 'widget' },
    'PSM-E-HOOK' => { gem: 'widget', hooks: 'postinstall, binding.gyp' },
    'PSM-E-SPEC' => { gem: 'widget', name: 'x', spec: 'file:../x' },
    'PSM-E-ALIAS' => { gem: 'widget', name: 'x', spec: 'npm:@rubygems/other@*' },
    'PSM-E-REACT' => { gem: 'widget', packages: 'react and react-dom' },
    'PSM-E-CROSS-GEM' => { gem: 'widget', other: 'other' },
    'PSM-E-NO-MANAGER' => {},
    'PSM-E-MANAGER-CONFLICT' => { signals: 'pnpm and bun' },
    'PSM-E-UNSUPPORTED-MANAGER' => { manager: 'yarn' },
    'PSM-E-BUN-LOCKB' => {},
    'PSM-E-MANAGER-MISSING' => { manager: 'pnpm' },
    'PSM-E-MANAGER-VERSION' => { manager: 'pnpm', version: '9.15.0',
                                 supported: '>= 11.0.0, < 12; >= 12.0.0, < 13' },
    'PSM-E-EXPERIMENTAL-FROZEN' => {},
    'PSM-E-BUN-LINKER' => {},
    'PSM-E-BUN-TRUSTED' => {},
    'PSM-E-NESTED-WORKSPACE' => { enclosing: '/src/monorepo' },
    'PSM-E-REGISTRATION' => { file: 'package.json' },
    'PSM-E-BUSY' => { holder: 'proscenium install (pid 4242)' },
    'PSM-E-NATIVE' => { command: 'pnpm install', status: 1 },
    'PSM-E-INTERRUPTED' => { command: 'pnpm install' },
    'PSM-E-CROSS-GEM-TARGET' => { gem: 'widget', other: 'other' },
    'PSM-E-CONFIG' => { detail: 'proscenium.json must have "schema": 1' },
    'PSM-E-PROBLEMS' => { count: 2 },
    'PSM-E-DRIFT' => { count: 2, list: "  - widget: its context is out of date\n  " \
                                       '- pnpm-lock.yaml is missing' },
    'PSM-E-REGISTRY-TARBALL' => { packages: '@rubygems/widget' },
    'PSM-E-WORKSPACE-MISSING' => { gems: 'widget', manager: 'bun' },
    'PSM-E-PEER-SPLIT' => { gem: 'widget', package: 'react', manager: 'pnpm' },
    'PSM-E-OWNED-DIR' => { entries: 'mine' }
  }.freeze

  def render(error, json:)
    out = StringIO.new
    err = StringIO.new
    Proscenium::CLI::Reporter.new(out:, err:, json:).error(error)
    json ? out.string : err.string
  end

  def golden(name, actual)
    path = File.join(GOLDEN, name)
    File.write(path, actual) if ENV['GOLDEN'] == 'update'

    assert_equal File.read(path), actual, "#{name} differs from its golden (GOLDEN=update)"
  end

  it 'has an example for every code' do
    assert_equal Proscenium::CLI::Error::CATALOG.keys.sort, EXAMPLES.keys.sort
  end

  Proscenium::CLI::Error::CATALOG.each_key do |code|
    it "renders #{code}" do
      error = Proscenium::CLI::Error.new(code, **EXAMPLES.fetch(code))

      golden("#{code}.txt", render(error, json: false))
      golden("#{code}.json", render(error, json: true))
    end
  end

  it 'maps every code to a documented exit status' do
    Proscenium::CLI::Error::CATALOG.each do |code, (status, *)|
      assert_includes 1..8, Proscenium::CLI::Error::EXIT.fetch(status), code
    end
  end
end
