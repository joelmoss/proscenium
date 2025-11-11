# frozen_string_literal: true

class Proscenium::HelperTest < ActionDispatch::IntegrationTest
  describe '#css_module' do
    it 'transforms class names beginning with @' do
      page = Capybara::Node::Simple.new(CssmHelperController.render(:index))

      assert page.has_css?('body.body_fc789ed8')
      assert page.has_css?('h2.view_38fff6bc')
      assert page.has_css?('div.partial_90b89cfc.world')
    end
  end

  describe '#include_stylesheets' do
    it 'includes side loaded stylesheets' do
      get '/'

      assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/bare.css"]'
      assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/home.css"]'
    end
  end

  describe '#include_javascripts' do
    it 'includes side loaded javascripts' do
      get '/'

      assert_dom 'script[src="/app/views/layouts/bare.js"]'
      assert_dom 'script[src="/app/views/bare_pages/home.js"]'
    end
  end

  describe '#include_assets' do
    it 'includes side loaded assets' do
      get '/include_assets'

      assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/bare.css"]'
      assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/include_assets.css"]'
      assert_dom 'script[src="/app/views/pages/_side.js"]'
      assert_dom 'script[src="/app/views/layouts/bare.js"]'
      assert_dom 'script[src="/app/views/bare_pages/include_assets.js"]'
    end
  end

  describe '#sideload_assets' do
    context 'false in controller' do
      it 'does not include assets' do
        BarePagesController.sideload_assets false
        get '/'

        assert_not_includes @response.body, '<script'
        assert_not_includes @response.body, '<link'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'proc in controller' do
      it 'does not include assets' do
        BarePagesController.sideload_assets proc { request.xhr? }
        get '/'

        assert_not_includes @response.body, '<script'
        assert_not_includes @response.body, '<link'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'css: false in controller' do
      it 'does not includes stylesheets' do
        BarePagesController.sideload_assets css: false
        get '/'

        assert_not_includes @response.body, '<link rel="stylesheet"'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'css: { class: :foo } in controller' do
      it 'sets attributes on stylesheets' do
        BarePagesController.sideload_assets css: { class: :foo }
        get '/'

        assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/bare.css"][class="foo"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/home.css"][class="foo"]'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'js: false in controller' do
      it 'does not includes javascripts' do
        BarePagesController.sideload_assets js: false
        get '/'

        assert_not_includes @response.body, '<script src="'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'js: { defer: true } in controller' do
      it 'sets attributes on javascripts' do
        BarePagesController.sideload_assets js: { defer: true }
        get '/'

        assert_dom 'script[src="/app/views/layouts/bare.js"][defer="defer"]'
        assert_dom 'script[src="/app/views/bare_pages/home.js"][defer="defer"]'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'false in controller; true in view template' do
      it 'excludes all except view template assets' do
        BarePagesController.sideload_assets false
        get '/include_assets?sideload_view_assets=true'

        assert_dom 'script[src="/app/views/bare_pages/include_assets.js"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/include_assets.css"]'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'false in controller; true in partials' do
      it 'excludes all except partial assets' do
        BarePagesController.sideload_assets false
        get '/include_assets?sideload_partial_assets=true'

        assert_dom 'script[src="/app/views/pages/_side.js"]'
      ensure
        BarePagesController.sideload_assets nil
      end
    end

    context 'false in view template' do
      it 'does not include template view assets' do
        get '/include_assets?sideload_view_assets=false'

        assert_dom 'link[rel="stylesheet"][href="/app/views/pages/_side_layout.css"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/bare.css"]'
        assert_dom 'script[src="/app/views/pages/_side.js"]'
        assert_dom 'script[src="/app/views/layouts/bare.js"]'
      end
    end

    context 'false in layout template' do
      it 'does not include template layout assets' do
        get '/include_assets?sideload_layout_assets=false'

        assert_dom 'link[rel="stylesheet"][href="/app/views/pages/_side_layout.css"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/include_assets.css"]'
        assert_dom 'script[src="/app/views/pages/_side.js"]'
        assert_dom 'script[src="/app/views/bare_pages/include_assets.js"]'
      end
    end

    context 'false in partial' do
      it 'does not include partial assets' do
        get '/include_assets?sideload_partial_assets=false'

        assert_dom 'link[rel="stylesheet"][href="/app/views/pages/_side_layout.css"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/bare.css"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/include_assets.css"]'
        assert_dom 'script[src="/app/views/layouts/bare.js"]'
        assert_dom 'script[src="/app/views/bare_pages/include_assets.js"]'
      end
    end

    context 'false in partial layout' do
      it 'does not include partial layout assets' do
        get '/include_assets?sideload_partial_layout_assets=false'

        assert_dom 'link[rel="stylesheet"][href="/app/views/layouts/bare.css"]'
        assert_dom 'link[rel="stylesheet"][href="/app/views/bare_pages/include_assets.css"]'
        assert_dom 'script[src="/app/views/pages/_side.js"]'
        assert_dom 'script[src="/app/views/layouts/bare.js"]'
        assert_dom 'script[src="/app/views/bare_pages/include_assets.js"]'
      end
    end
  end
end
