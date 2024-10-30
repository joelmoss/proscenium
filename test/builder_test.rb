# frozen_string_literal: true

require 'test_helper'

class Proscenium::BuilderTest < ActiveSupport::TestCase
  before do
    Proscenium.config.env_vars = Set.new
  end

  let(:subject) { Proscenium::Builder }

  context '.build_to_path' do
    it 'builds multiple files' do
      exp = %(
        lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;
        lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js
      ).gsub(/[[:space:]]/, '')

      assert_equal exp,
                   subject.build_to_path('lib/code_splitting/son.js;lib/code_splitting/daughter.js')
    end
  end

  context '.build_to_string' do
    it 'replaces NODE_ENV and RAILS_ENV' do
      assert_includes subject.build_to_string('lib/env/env.js'), 'console.log("testtest")'
    end

    context 'config.env_vars' do
      it 'replaces' do
        Proscenium.config.env_vars << 'USER_NAME'
        ENV['USER_NAME'] = 'joelmoss'

        assert_includes subject.build_to_string('lib/env/extra.js'), 'console.log("joelmoss")'
      end
    end

    context 'unknown path' do
      it 'raise' do
        error = assert_raises(Proscenium::Builder::BuildError) do
          subject.build_to_string('unknown.js')
        end

        assert_equal 'Could not resolve "unknown.js"', error.message
      end
    end
  end

  context '.resolve' do
    it 'resolves value' do
      assert_equal '/packages/mypackage/index.js', subject.resolve('mypackage')
    end
  end
end
