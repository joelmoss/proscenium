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
      PagesController.render :home

      expect(Proscenium::Importer.imported).to be(:nil?)
    end

    it 'does not side load partial' do
      PagesController.render :sideloadpartial

      expect(Proscenium::Importer.imported).to be(:nil?)
    end

    it 'does not side load vendored gem' do
      PagesController.render :vendored_gem

      expect(Proscenium::Importer.imported).to be(:nil?)
    end

    it 'does not side loads external gem' do
      PagesController.render :external_gem

      expect(Proscenium::Importer.imported).to be(:nil?)
    end
  end

  it 'side loads layout and view' do
    PagesController.render :home

    expect(Proscenium::Importer.imported).to be == {
      '/app/views/layouts/application.js' => { sideloaded: true },
      '/app/views/layouts/application.css' => { sideloaded: true },
      '/app/views/pages/home.js' => { sideloaded: true },
      '/app/views/pages/home.css' => { sideloaded: true }
    }
  end

  it 'side loads variant' do
    skip 'fixme'
    pp PagesController.new.request
    pp PagesController.render :variant
  end

  it 'side loads partial' do
    PagesController.render :sideloadpartial

    expect(Proscenium::Importer.imported).to be == {
      '/app/views/layouts/application.js' => { sideloaded: true },
      '/app/views/layouts/application.css' => { sideloaded: true },
      '/app/views/pages/_side.js' => { sideloaded: true },
      '/app/views/pages/_side.module.css' => { sideloaded: true, digest: '08ab1f89' },
      '/app/views/pages/_side_layout.css' => { sideloaded: true }
    }
  end

  it 'side loads vendored gem' do
    PagesController.render :vendored_gem

    expect(Proscenium::Importer.imported).to be == {
      '/app/views/layouts/application.js' => { sideloaded: true },
      '/app/views/layouts/application.css' => { sideloaded: true },
      '/vendor/gem1/app/components/flash/component.jsx' => { sideloaded: true, lazy: false },
      '/lib/manager/index.jsx' => {}
    }
  end

  it 'side loads external gem' do
    PagesController.render :external_gem

    expect(Proscenium::Importer.imported).to be == {
      '/app/views/layouts/application.js' => { sideloaded: true },
      '/app/views/layouts/application.css' => { sideloaded: true },
      '/node_modules/.pnpm/file+..+external+gem2/node_modules/gem2/app/components/flash/component.jsx' => { sideloaded: true, lazy: false },
      '/lib/manager/index.jsx' => {}
    }
  end
end
