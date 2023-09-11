# frozen_string_literal: true

describe Proscenium::Builder do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
    Proscenium.config.env_vars = Set.new
  end

  with '.build' do
    it 'builds multiple files' do
      expect(subject.build('lib/code_splitting/son.js;lib/code_splitting/daughter.js')).to be == %(
      lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;
      lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js
    ).gsub(/[[:space:]]/, '')
    end

    it 'replaces NODE_ENV and RAILS_ENV' do
      expect(subject.build('lib/env/env.js')).to include 'console.log("testtest")'
    end

    with 'config.env_vars' do
      it 'replaces' do
        Proscenium.config.env_vars << 'USER_NAME'
        ENV['USER_NAME'] = 'joelmoss'

        expect(subject.build('lib/env/extra.js')).to include 'console.log("joelmoss")'
      end
    end

    with 'unknown path' do
      it 'raise' do
        expect do
          subject.build('unknown.js')
        end.to raise_exception(Proscenium::Builder::BuildError,
                               message: be == "Failed to build 'unknown.js' -- Could not resolve \"unknown.js\"")
      end
    end
  end

  with '.resolve' do
    it 'resolves value' do
      expect(subject.resolve('is-ip')).to be == '/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js'
    end
  end
end
