# frozen_string_literal: true

describe Proscenium::Resolver do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with '.resolve' do
    with value: './foo' do
      it 'raises' do
        expect do
          subject.resolve(value)
        end.to raise_exception(ArgumentError, message: be == 'path must be an absolute file system or URL path')
      end
    end

    with 'unknown path', value: 'unknown' do
      it 'raises' do
        expect do
          subject.resolve(value)
        end.to raise_exception(Proscenium::Builder::ResolveError)
      end
    end

    with 'bare specifier (NPM package)', value: 'mypackage' do
      it 'resolves' do
        expect(subject.resolve(value)).to be == '/packages/mypackage/index.js'
      end
    end

    with 'absolute file system path', value: Rails.root.join('lib/foo.js').to_s do
      it 'resolves' do
        expect(subject.resolve(value)).to be == '/lib/foo.js'
      end
    end

    with 'absolute URL path', value: '/lib/foo.js' do
      it 'resolves' do
        expect(subject.resolve(value)).to be == '/lib/foo.js'
      end
    end

    with '@proscenium runtime', value: '@proscenium/react-manager/index.jsx' do
      it 'resolves' do
        expect(subject.resolve(value)).to be == '/@proscenium/react-manager/index.jsx'
      end
    end
  end
end
