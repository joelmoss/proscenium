# frozen_string_literal: true

require_relative 'helper'

# How the CLI looks in a terminal (#154): a labelled problem, what to do about it, and the code
# last. Colour only where a person is reading: a terminal, without NO_COLOR or TERM=dumb.
describe Proscenium::CLI::Reporter do
  Reporter = Proscenium::CLI::Reporter

  # An IO that says it is a terminal.
  class TTY < StringIO
    def tty? = true
  end

  def error = Proscenium::CLI::Error.new('PSM-E-INTERRUPTED', command: 'pnpm install')

  def with_env(env)
    saved = env.keys.to_h { [it, ENV.fetch(it, nil)] }
    env.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  it 'labels an error, then says how to fix it, with the code last' do
    err = StringIO.new
    Reporter.new(out: StringIO.new, err:).error(error)

    assert_equal "Error: #{error.message}\n\nTo fix: #{error.fix}\n(PSM-E-INTERRUPTED)\n\n",
                 err.string
  end

  it 'labels a warning' do
    err = StringIO.new
    warning = Proscenium::CLI::Error.new('PSM-W-END-OF-LIFE', manager: 'pnpm', version: '11.0.0',
                                                              eol: '2027-04-30')
    Reporter.new(out: StringIO.new, err:).warning(warning)

    assert err.string.start_with?("Warning: #{warning.message}\n\nTo fix: ")
    assert err.string.end_with?("(PSM-W-END-OF-LIFE)\n\n"), 'a blank line ends it'
  end

  it 'colours a terminal, and nothing else' do
    with_env('NO_COLOR' => nil, 'TERM' => 'xterm-256color') do
      err = TTY.new
      Reporter.new(out: StringIO.new, err:).error(error)

      assert_includes err.string, "\e[1;31mError:\e[0m "
      assert_includes err.string, "\e[2m(PSM-E-INTERRUPTED)\e[0m"

      plain = StringIO.new
      Reporter.new(out: StringIO.new, err: plain).error(error)

      refute_includes plain.string, "\e["
    end
  end

  it 'does not colour with NO_COLOR or TERM=dumb' do
    [{ 'NO_COLOR' => '1', 'TERM' => 'xterm' },
     { 'NO_COLOR' => nil, 'TERM' => 'dumb' }].each do |env|
      with_env(env) do
        err = TTY.new
        Reporter.new(out: StringIO.new, err:).error(error)

        refute_includes err.string, "\e[", env.inspect
      end
    end
  end

  it 'paints text for a terminal, and leaves JSON plain' do
    with_env('NO_COLOR' => nil, 'TERM' => 'xterm') do
      assert_equal "\e[32mok\e[0m", Reporter.new(out: TTY.new, err: TTY.new).paint('ok', :green)
      assert_equal 'ok', Reporter.new(out: TTY.new, err: TTY.new, json: true).paint('ok', :green)
    end
  end

  it 'colours a diff by line' do
    with_env('NO_COLOR' => nil, 'TERM' => 'xterm') do
      reporter = Reporter.new(out: TTY.new, err: TTY.new)
      painted = reporter.paint_diff("--- a\n+++ a\n@@ -0,0 +1 @@\n+x\n-y\n")

      assert_equal "\e[1m--- a\e[0m\n\e[1m+++ a\e[0m\n\e[36m@@ -0,0 +1 @@\e[0m\n" \
                   "\e[32m+x\e[0m\n\e[31m-y\e[0m\n", painted
    end
  end

  it 'counts in words' do
    assert_equal '1 gem', Reporter.count(1, 'gem')
    assert_equal '2 gems', Reporter.count(2, 'gem')
    assert_equal '2 dependencies', Reporter.count(2, 'dependency', 'dependencies')
  end
end
