# frozen_string_literal: true

describe Proscenium::Importer do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with '.import' do
    it 'single file' do
      subject.import '/app/views/layouts/application.js'

      expect(subject.imported).to be == { '/app/views/layouts/application.js' => {} }
    end

    it 'passes additional kwargs' do
      subject.import '/app/views/layouts/application.js', name: 'bob'

      expect(subject.imported).to be == {
        '/app/views/layouts/application.js' => { name: 'bob' }
      }
    end

    it 'concatanates multiple calls' do
      subject.import '/app/views/layouts/application.js'
      subject.import '/app/views/layouts/application.css'

      expect(subject.imported).to be == {
        '/app/views/layouts/application.js' => {},
        '/app/views/layouts/application.css' => {}
      }
    end

    it 'deduplicates paths' do
      subject.import '/app/views/layouts/application.js'
      subject.import '/app/views/layouts/application.js'

      expect(subject.imported).to be == { '/app/views/layouts/application.js' => {} }
    end

    it 'imports @proscenium/* runtime files' do
      subject.import resolve: '@proscenium/react-manager/index.jsx'

      expect(subject.imported).to be == { '/@proscenium/react-manager/index.jsx' => {} }
    end
  end

  with '.sideload' do
    with 'js and css' do
      it 'sideloads' do
        mock_files 'app/views/user.rb', 'app/views/user.js', 'app/views/user.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        expect(subject.imported).to be == {
          '/app/views/user.js' => { sideloaded: true },
          '/app/views/user.css' => { sideloaded: true }
        }
      end
    end

    with 'no js, no css' do
      it 'sideloads nothing' do
        mock_file 'app/views/user.rb' do
          Proscenium::Importer.sideload Rails.root.join('app/views/user.rb')
        end

        expect(subject.imported).to be_nil
      end
    end

    with 'no js' do
      it 'sideloads' do
        mock_files 'app/views/user.rb', 'app/views/user.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        expect(subject.imported).to be == { '/app/views/user.css' => { sideloaded: true } }
      end
    end

    with '.module.css and .css' do
      it 'sideloads css module' do
        mock_files 'app/views/user.rb', 'app/views/user.css', 'app/views/user.module.css' do
          subject.sideload Rails.root.join('app/views/user.rb')
        end

        expect(subject.imported).to be == { '/app/views/user.module.css' => {
          sideloaded: true, digest: 'ab65a4fd'
        } }
      end
    end
  end

  def mock_file(*paths)
    FakeFS.with_fresh do
      paths.each do |path|
        path = Rails.root.join(path)
        path.dirname.mkpath
        FileUtils.touch(path.to_s, noop: true)
      end

      yield
    end
  end
  alias_method :mock_files, :mock_file
end
