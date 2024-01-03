# frozen_string_literal: true

require 'system_testing'

describe Proscenium::Helper do
  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  attr_reader :page

  def render(output)
    @page = Capybara::Node::Simple.new(output)
  end

  describe '#css_module' do
    it 'transforms class names beginning with @' do
      render CssmHelperController.render :index

      expect(page.has_css?('body.body-ead1b5bc')).to be == true
      expect(page.has_css?('h2.view-ba1ab2b7')).to be == true
      expect(page.has_css?('div.partial-7800dcdf.world')).to be == true
    end
  end

  describe '#include_stylesheets' do
    include_context SystemTest

    it 'includes side loaded stylesheets' do
      visit '/'

      expect(page.html).to include '<link rel="stylesheet" href="/app/views/layouts/bare.css">'
      expect(page.html).to include '<link rel="stylesheet" href="/app/views/bare_pages/home.css">'
    end
  end

  describe '#include_javascripts' do
    include_context SystemTest

    it 'includes side loaded javascripts' do
      visit '/'

      expect(page.html).to include '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>'
      expect(page.html).to include '<script src="/assets/app/views/bare_pages/home$V6EQNOC2$.js"></script>'
    end
  end

  describe '#include_assets' do
    include_context SystemTest

    it 'includes side loaded assets' do
      visit '/include_assets'

      expect(page.html).to include(
        '<head>' \
        '<link rel="stylesheet" href="/app/views/pages/_side.module.css">' \
        '<link rel="stylesheet" href="/app/views/pages/_side_layout.css">' \
        '<link rel="stylesheet" href="/app/views/layouts/bare.css">' \
        '<link rel="stylesheet" href="/app/views/bare_pages/include_assets.css">' \
        '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
        '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
        '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
        "\n</head>"
      )
    end
  end

  describe '#sideload_assets' do
    include_context SystemTest

    with 'false in controller' do
      it 'does not include assets' do
        BarePagesController.sideload_assets false
        visit '/'

        expect(page.html).to include '<head></head>'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'proc in controller' do
      it 'does not include assets' do
        BarePagesController.sideload_assets proc { request.xhr? }
        visit '/'

        expect(page.html).to include '<head></head>'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'css: false in controller' do
      it 'does not includes stylesheets' do
        BarePagesController.sideload_assets css: false
        visit '/'

        expect(page.html).not.to include '<link rel="stylesheet"'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'css: { class: :foo } in controller' do
      it 'sets attributes on stylesheets' do
        BarePagesController.sideload_assets css: { class: :foo }
        visit '/'

        expect(page.html).to include '<link rel="stylesheet" href="/app/views/layouts/bare.css" class="foo">'
        expect(page.html).to include '<link rel="stylesheet" href="/app/views/bare_pages/home.css" class="foo">'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'js: false in controller' do
      it 'does not includes javascripts' do
        BarePagesController.sideload_assets js: false
        visit '/'

        expect(page.html).not.to include '<script src="'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'js: { defer: true } in controller' do
      it 'sets attributes on javascripts' do
        BarePagesController.sideload_assets js: { defer: true }
        visit '/'

        expect(page.html).to include '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js" defer="defer"></script>'
        expect(page.html).to include '<script src="/assets/app/views/bare_pages/home$V6EQNOC2$.js" defer="defer"></script>'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'false in controller; true in view template' do
      it 'excludes all except view template assets' do
        BarePagesController.sideload_assets false
        visit '/include_assets?sideload_view_assets=true'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/app/views/bare_pages/include_assets.js"></script>' \
          "\n</head>"
        )
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'false in controller; true in partials' do
      it 'excludes all except partial assets' do
        BarePagesController.sideload_assets false
        visit '/include_assets?sideload_partial_assets=true'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/pages/_side.module.css">' \
          '<script src="/app/views/pages/_side.js"></script>' \
          "\n</head>"
        )
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    with 'false in view template' do
      it 'does not include template view assets' do
        visit '/include_assets?sideload_view_assets=false'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/pages/_side.module.css">' \
          '<link rel="stylesheet" href="/app/views/pages/_side_layout.css">' \
          '<link rel="stylesheet" href="/app/views/layouts/bare.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
          "\n</head>"
        )
      end
    end

    with 'false in layout template' do
      it 'does not include template layout assets' do
        visit '/include_assets?sideload_layout_assets=false'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/pages/_side.module.css">' \
          '<link rel="stylesheet" href="/app/views/pages/_side_layout.css">' \
          '<link rel="stylesheet" href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      end
    end

    with 'false in partial' do
      it 'does not include partial assets' do
        visit '/include_assets?sideload_partial_assets=false'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/pages/_side_layout.css">' \
          '<link rel="stylesheet" href="/app/views/layouts/bare.css">' \
          '<link rel="stylesheet" href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      end
    end

    with 'false in partial layout' do
      it 'does not include partial layout assets' do
        visit '/include_assets?sideload_partial_layout_assets=false'

        expect(page.html).to include(
          '<head>' \
          '<link rel="stylesheet" href="/app/views/pages/_side.module.css">' \
          '<link rel="stylesheet" href="/app/views/layouts/bare.css">' \
          '<link rel="stylesheet" href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      end
    end
  end
end
