# frozen_string_literal: true

require_relative 'helper'

# Golden output for every error code: the human text and the JSON event, pinned in
# test/cli/golden/. Run with GOLDEN=update to rewrite them after a deliberate change.
describe Proscenium::CLI::Error do
  GOLDEN = File.expand_path('golden', __dir__)

  # Arguments that render each code. A new code needs an entry here, which gives it a golden.
  EXAMPLES = {
    'PSM-E-USAGE' => { detail: 'Unknown command: frobnicate' },
    'PSM-E-INTERNAL' => { detail: 'ArgumentError: boom' }
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
