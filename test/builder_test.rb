# frozen_string_literal: true

require 'test_helper'

class Proscenium::BuilderTest < ActiveSupport::TestCase
  before do
    subject.reset_config!
    Proscenium.config.env_vars = Set.new
  end

  let(:subject) { Proscenium::Builder }

  describe '.build_to_string' do
    it 'replaces NODE_ENV and RAILS_ENV' do
      result = subject.build_to_string('lib/env/env.js')
      assert_includes result[:response], 'console.log("testtest")'
    end

    context 'config.env_vars' do
      it 'replaces' do
        Proscenium.config.env_vars << 'USER_NAME'
        ENV['USER_NAME'] = 'joelmoss'

        result = subject.build_to_string('lib/env/extra.js')
        assert_includes result[:response], 'console.log("joelmoss")'
      end
    end

    it 'raises on unknown path' do
      error = assert_raises(Proscenium::Builder::BuildError) do
        subject.build_to_string('unknown.js')
      end

      assert_equal 'Failed to build unknown.js - Could not resolve "unknown.js"', error.message
    end

    it 'raises on non-bare specifier' do
      error = assert_raises(Proscenium::Builder::BuildError) do
        subject.build_to_string('/unknown.js')
      end

      assert_equal 'Failed to build /unknown.js - Could not resolve "/unknown.js" - ' \
                   'Entrypoints must be bare specifiers',
                   error.message
    end

    # A note is where a recovered Go panic carries its stack, and where a failure inside a nested
    # build names its importer. Constructed directly: nothing in the fixtures panics on purpose.
    it 'appends notes to the message on their own lines' do
      error = Proscenium::Builder::BuildError.new('x.js', {
        Text: 'panic: boom (in OnLoad callback)',
        Location: { File: 'lib/x.js', Line: 2, Column: 1 },
        Notes: [{ Text: 'stack line one' }, { Text: 'stack line two' }]
      }.to_json)

      assert_equal "Failed to build x.js - panic: boom (in OnLoad callback) at lib/x.js:2:1\n" \
                   "stack line one\nstack line two",
                   error.message
    end
  end

  describe '.compile' do
    it 'raises with the messages when the build fails' do
      error = assert_raises(Proscenium::Builder::CompileError) do
        subject.compile(Precompile: [])
      end

      assert_includes error.message, 'Failed to compile assets - No precompile paths specified - '
      assert_equal 1, error.messages['Errors'].length
    end
  end

  describe '.resolve' do
    it 'resolves value' do
      assert_equal [
        '/node_modules/pkg/index.js',
        Proscenium.root.join('fixtures/dummy/node_modules/pkg/index.js').to_s
      ], subject.resolve('pkg')
    end

    # Go answers a URL with no file path. Pinned on this side as well, because the empty string
    # crosses the FFI and `Proscenium::Resolver.resolve` hands it on as `abs_path`.
    it 'returns an empty absolute path for a URL' do
      assert_equal ['https://cdn.example/x.js', ''], subject.resolve('https://cdn.example/x.js')
    end

    # The FFI hands back ASCII-8BIT, but these are paths and Go writes them as UTF-8. Left binary, a
    # non-ASCII character is several "characters" to anything that works on the string.
    it 'returns paths tagged as UTF-8' do
      url_path, abs_path = subject.resolve('pkg')

      assert_equal Encoding::UTF_8, url_path.encoding
      assert_equal Encoding::UTF_8, abs_path.encoding
    end
  end

  describe 'config overrides' do
    it 'builds identically when no overrides are given' do
      first = subject.build_to_string('lib/foo.js')
      second = subject.build_to_string('lib/foo.js')

      assert_equal first[:response], second[:response]
    end

    it 'passes Bundle through to the builder' do
      import_of_foo4 = %r{import[^;]*"/lib/foo4\.js"}

      bundled = subject.build_to_string('lib/import_absolute_module.js')
      unbundled = subject.build_to_string('lib/import_absolute_module.js', Bundle: false)

      assert_match import_of_foo4, unbundled[:response]
      refute_match import_of_foo4, bundled[:response]
    end

    it 'passes Write through to the builder' do
      output = Proscenium.root.join('fixtures/dummy/public/assets')
      FileUtils.rm_rf output

      result = subject.build_to_string('lib/foo.js', Write: false)

      assert_includes result[:response], 'console.log("/lib/foo.js")'
      assert_empty Dir.exist?(output) ? Dir.children(output) : []
    end

    # Two threads building with different overrides must not receive each other's config pointer.
    # Without the mutex the failure mode is a build made with the wrong config rather than an
    # exception, so this asserts on the built output.
    it 'is thread safe across differing overrides' do
      bundled = []
      unbundled = []
      mutex = Mutex.new

      threads = Array.new(12) do |i|
        Thread.new do
          if i.even?
            out = subject.build_to_string('lib/import_absolute_module.js')
            mutex.synchronize { bundled << out[:response] }
          else
            out = subject.build_to_string('lib/import_absolute_module.js', Bundle: false)
            mutex.synchronize { unbundled << out[:response] }
          end
        end
      end
      threads.each(&:join)

      import_of_foo4 = %r{import[^;]*"/lib/foo4\.js"}

      assert_equal 6, bundled.size
      assert_equal 6, unbundled.size
      bundled.each { |r| refute_match import_of_foo4, r }
      unbundled.each { |r| assert_match import_of_foo4, r }
    end
  end
end
