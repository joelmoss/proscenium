# frozen_string_literal: true

require 'application_system_test_case'

# rubocop:disable Layout/LineLength
class Proscenium::HelperTest < ApplicationSystemTestCase
  describe '#css_module' do
    it 'transforms class names beginning with @' do
      page = Capybara::Node::Simple.new(CssmHelperController.render(:index))

      assert page.has_css?('body.body-ead1b5bc')
      assert page.has_css?('h2.view-ba1ab2b7')
      assert page.has_css?('div.partial-7800dcdf.world')
    end
  end

  describe '#include_stylesheets' do
    it 'includes side loaded stylesheets' do
      visit '/'

      assert_includes page.html, <<~HTML.squish
        <link rel="stylesheet" href="/assets/app/views/layouts/bare$2KHIH3MU$.css" data-original-href="/app/views/layouts/bare.css">
      HTML
      assert_includes page.html, <<~HTML.squish
        <link rel="stylesheet" href="/assets/app/views/bare_pages/home$7TUB27RG$.css" data-original-href="/app/views/bare_pages/home.css">
      HTML
    end
  end

  describe '#include_javascripts' do
    it 'includes side loaded javascripts' do
      visit '/'

      assert_includes page.html, <<~HTML.squish
        <script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>
      HTML
      assert_includes page.html, <<~HTML.squish
        <script src="/assets/app/views/bare_pages/home$V6EQNOC2$.js"></script>
      HTML
    end
  end

  describe '#include_assets' do
    it 'includes side loaded assets' do
      visit '/include_assets'

      assert_includes(
        page.html,
        '<head>' \
        '<link rel="stylesheet" href="/assets/app/views/pages/_side.module$MJ3DIFXX$.css" data-original-href="/app/views/pages/_side.module.css">' \
        '<link rel="stylesheet" href="/assets/app/views/pages/_side_layout$K6XSAKOZ$.css" data-original-href="/app/views/pages/_side_layout.css">' \
        '<link rel="stylesheet" href="/assets/app/views/layouts/bare$2KHIH3MU$.css" data-original-href="/app/views/layouts/bare.css">' \
        '<link rel="stylesheet" href="/assets/app/views/bare_pages/include_assets$VQXNR2SE$.css" data-original-href="/app/views/bare_pages/include_assets.css">' \
        '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
        '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
        '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
        "\n</head>"
      )
    end
  end

  describe '#sideload_assets' do
    context 'false in controller' do
      it 'does not include assets' do
        BarePagesController.sideload_assets false
        visit '/'

        assert_includes page.html, '<head></head>'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'proc in controller' do
      it 'does not include assets' do
        BarePagesController.sideload_assets proc { request.xhr? }
        visit '/'

        assert_includes page.html, '<head></head>'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'css: false in controller' do
      it 'does not includes stylesheets' do
        BarePagesController.sideload_assets css: false
        visit '/'

        assert_not_includes page.html, '<link rel="stylesheet"'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'css: { class: :foo } in controller' do
      it 'sets attributes on stylesheets' do
        BarePagesController.sideload_assets css: { class: :foo }
        visit '/'

        assert_includes(
          page.html,
          '<link rel="stylesheet" href="/assets/app/views/layouts/bare$2KHIH3MU$.css" class="foo" data-original-href="/app/views/layouts/bare.css">'
        )
        assert_includes(
          page.html,
          '<link rel="stylesheet" href="/assets/app/views/bare_pages/home$7TUB27RG$.css" class="foo" data-original-href="/app/views/bare_pages/home.css">'
        )
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'js: false in controller' do
      it 'does not includes javascripts' do
        BarePagesController.sideload_assets js: false
        visit '/'

        assert_not_includes page.html, '<script src="'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'js: { defer: true } in controller' do
      it 'sets attributes on javascripts' do
        BarePagesController.sideload_assets js: { defer: true }
        visit '/'

        assert_includes(
          page.html,
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js" defer="defer"></script>'
        )
        assert_includes(
          page.html,
          '<script src="/assets/app/views/bare_pages/home$V6EQNOC2$.js" defer="defer"></script>'
        )
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'false in controller; true in view template' do
      it 'excludes all except view template assets' do
        BarePagesController.sideload_assets false
        visit '/include_assets?sideload_view_assets=true'

        assert_includes(
          page.html,
          '<head>' \
          '<link rel="stylesheet" href="/assets/app/views/bare_pages/include_assets$VQXNR2SE$.css" data-original-href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'false in controller; true in partials' do
      it 'excludes all except partial assets' do
        BarePagesController.sideload_assets false
        visit '/include_assets?sideload_partial_assets=true'

        assert_includes(
          page.html,
          '<head>' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side.module$MJ3DIFXX$.css" data-original-href="/app/views/pages/_side.module.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          "\n</head>"
        )
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'false in view template' do
      it 'does not include template view assets' do
        visit '/include_assets?sideload_view_assets=false'

        assert_includes(
          page.html,
          '<head>' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side.module$MJ3DIFXX$.css" data-original-href="/app/views/pages/_side.module.css">' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side_layout$K6XSAKOZ$.css" data-original-href="/app/views/pages/_side_layout.css">' \
          '<link rel="stylesheet" href="/assets/app/views/layouts/bare$2KHIH3MU$.css" data-original-href="/app/views/layouts/bare.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
          "\n</head>"
        )
      end
    end

    context 'false in layout template' do
      it 'does not include template layout assets' do
        visit '/include_assets?sideload_layout_assets=false'

        assert_includes(
          page.html,
          '<head>' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side.module$MJ3DIFXX$.css" data-original-href="/app/views/pages/_side.module.css">' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side_layout$K6XSAKOZ$.css" data-original-href="/app/views/pages/_side_layout.css">' \
          '<link rel="stylesheet" href="/assets/app/views/bare_pages/include_assets$VQXNR2SE$.css" data-original-href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      end
    end

    context 'false in partial' do
      it 'does not include partial assets' do
        visit '/include_assets?sideload_partial_assets=false'

        assert_includes(
          page.html,
          '<head>' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side_layout$K6XSAKOZ$.css" data-original-href="/app/views/pages/_side_layout.css">' \
          '<link rel="stylesheet" href="/assets/app/views/layouts/bare$2KHIH3MU$.css" data-original-href="/app/views/layouts/bare.css">' \
          '<link rel="stylesheet" href="/assets/app/views/bare_pages/include_assets$VQXNR2SE$.css" data-original-href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      end
    end

    context 'false in partial layout' do
      it 'does not include partial layout assets' do
        visit '/include_assets?sideload_partial_layout_assets=false'

        assert_includes(
          page.html,
          '<head>' \
          '<link rel="stylesheet" href="/assets/app/views/pages/_side.module$MJ3DIFXX$.css" data-original-href="/app/views/pages/_side.module.css">' \
          '<link rel="stylesheet" href="/assets/app/views/layouts/bare$2KHIH3MU$.css" data-original-href="/app/views/layouts/bare.css">' \
          '<link rel="stylesheet" href="/assets/app/views/bare_pages/include_assets$VQXNR2SE$.css" data-original-href="/app/views/bare_pages/include_assets.css">' \
          '<script src="/assets/app/views/pages/_side$V4GARDXT$.js"></script>' \
          '<script src="/assets/app/views/layouts/bare$3VKYLDSX$.js"></script>' \
          '<script src="/assets/app/views/bare_pages/include_assets$CNRUTFVD$.js"></script>' \
          "\n</head>"
        )
      end
    end
  end
end
# rubocop:enable Layout/LineLength
