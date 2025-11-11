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
end
