# frozen_string_literal: true

describe Proscenium::SideLoad do
  def before
    Proscenium.config.side_load = true
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  with 'side load disabled' do
    def before
      super
      Proscenium.config.side_load = false
    end

    it 'does not side load layout and view' do
      BarePagesController.render :home

      expect(Proscenium::Importer.imported).to be(:nil?)
    end

    it 'does not side load partial' do
      BarePagesController.render :sideloadpartial

      expect(Proscenium::Importer.imported).to be(:nil?)
    end

    it 'does not side load vendored gem' do
      BarePagesController.render :vendored_gem

      expect(Proscenium::Importer.imported).to be(:nil?)
    end

    it 'does not side loads external gem' do
      BarePagesController.render :external_gem

      expect(Proscenium::Importer.imported).to be(:nil?)
    end
  end

  it 'side loads layout and view' do
    BarePagesController.render :home

    expect(Proscenium::Importer.imported).to be == {
      '/app/views/layouts/bare.js' => { sideloaded: true },
      '/app/views/layouts/bare.css' => { sideloaded: true },
      '/app/views/bare_pages/home.js' => { sideloaded: true },
      '/app/views/bare_pages/home.css' => { sideloaded: true }
    }
  end

  it 'side loads variant' do
    skip 'fixme'
    pp PagesController.new.request
    pp PagesController.render :variant
  end

  it 'side loads partial' do
    BarePagesController.render :sideloadpartial

    expect(Proscenium::Importer.imported).to be == {
      '/app/views/layouts/bare.js' => { sideloaded: true },
      '/app/views/layouts/bare.css' => { sideloaded: true },
      '/app/views/pages/_side.js' => { sideloaded: true },
      '/app/views/pages/_side.module.css' => { sideloaded: true, digest: '08ab1f89' },
      '/app/views/pages/_side_layout.css' => { sideloaded: true }
    }
  end

  it 'side loads vendored gem' do
    BarePagesController.render :vendored_gem

    expect(Proscenium::Importer.imported).to be == {
      '/@proscenium/react-manager/index.jsx' => { js: { type: :module } },
      '/gem1/app/components/flash/component.jsx' => { sideloaded: true, lazy: true },
      '/app/views/layouts/bare.js' => { sideloaded: true },
      '/app/views/layouts/bare.css' => { sideloaded: true }
    }
  end

  it 'side loads external gem' do
    BarePagesController.render :external_gem

    expect(Proscenium::Importer.imported).to be == {
      '/@proscenium/react-manager/index.jsx' => { js: { type: :module } },
      '/gem2/app/components/flash/component.jsx' => { sideloaded: true, lazy: true },
      '/app/views/layouts/bare.js' => { sideloaded: true },
      '/app/views/layouts/bare.css' => { sideloaded: true }
    }
  end
end
