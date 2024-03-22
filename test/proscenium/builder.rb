# frozen_string_literal: true

describe Proscenium::Builder do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
    Proscenium.config.env_vars = Set.new
  end

  with '.build_to_path' do
    it 'builds multiple files' do
      expect(subject.build_to_path('lib/code_splitting/son.js;lib/code_splitting/daughter.js')).to be == %(
        lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;
        lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js
        ).gsub(/[[:space:]]/, '')
    end
  end

  with '.build_to_string' do
    it 'replaces NODE_ENV and RAILS_ENV' do
      expect(subject.build_to_string('lib/env/env.js')).to include 'console.log("testtest")'
    end

    with 'config.env_vars' do
      it 'replaces' do
        Proscenium.config.env_vars << 'USER_NAME'
        ENV['USER_NAME'] = 'joelmoss'

        expect(subject.build_to_string('lib/env/extra.js')).to include 'console.log("joelmoss")'
      end
    end

    with 'unknown path' do
      it 'raise' do
        expect do
          subject.build_to_string('unknown.js')
        end.to raise_exception(Proscenium::Builder::BuildError,
                               message: be == 'Could not resolve "unknown.js"')
      end
    end
  end

  with '.resolve' do
    it 'resolves value' do
      expect(subject.resolve('mypackage')).to be == '/packages/mypackage/index.js'
    end
  end
end
