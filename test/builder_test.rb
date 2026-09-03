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
  end

  describe '.resolve' do
    it 'resolves value' do
      assert_equal [
        '/node_modules/pkg/index.js',
        Proscenium.root.join('fixtures/dummy/node_modules/pkg/index.js').to_s
      ], subject.resolve('pkg')
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
