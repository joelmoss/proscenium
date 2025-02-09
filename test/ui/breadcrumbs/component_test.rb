# frozen_string_literal: true

require 'test_helper'

class Proscenium::UI::Breadcrumbs::ComponentTest < ActiveSupport::TestCase
  extend ViewHelper

  before do
    controller.class.include Proscenium::UI::Breadcrumbs::Control
  end

  let(:subject) { Proscenium::UI::Breadcrumbs::Component }
  view -> { subject.new }

  it 'side loads CSS' do
    view
    imports = Proscenium::Importer.imported.keys

    assert_equal ['/proscenium/breadcrumbs/component.module.css'], imports
  end

  context '@hide_breadcrumbs = true' do
    it 'does not render' do
      controller.instance_variable_set :@hide_breadcrumbs, true

      assert_not view.has_selector?('ol')
    end
  end

  it 'shows home element by default' do
    assert_equal '/', view.find('ol li:first-child a')['href']
    assert view.has_selector?('ol li:first-child a>svg')
  end

  context "home_path: '/foo'" do
    view -> { Proscenium::UI::Breadcrumbs::Component.new home_path: '/foo' }

    it 'uses custom home path' do
      assert_equal '/foo', view.find('ol li:first-child a')['href']
    end
  end

  context 'with_home: false' do
    view -> { Proscenium::UI::Breadcrumbs::Component.new with_home: false }

    it 'does not show home element' do
      assert_not view.has_selector?('ol li')
    end
  end

  context 'redefined #home_template' do
    view lambda {
      Class.new(Proscenium::UI::Breadcrumbs::Component) do
        def self.source_path
          Proscenium::UI::Breadcrumbs::Component.source_path
        end

        def home_template
          super { 'Hello' }
        end
      end.new
    }

    it 'renders #home_template' do
      assert_equal '/', view.find('ol li:first-child a')['href']
      assert_equal 'Hello', view.find('ol li:first-child a').text
    end
  end

  describe '#add_breadcrumb' do
    view -> { Proscenium::UI::Breadcrumbs::Component.new with_home: false }

    context 'string name and path' do
      it 'renders breadcrumb as link' do
        controller.add_breadcrumb 'Foo', '/foo'

        assert view.find('ol li:first-child a').has_content?('Foo')
        assert_equal '/foo', view.find('ol li:first-child a')['href']
      end
    end

    context 'name only; as string' do
      it 'renders the name as-is, and does not render link' do
        controller.add_breadcrumb 'Foo'

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_not view.has_selector?('ol li:first-child a')
      end
    end

    context 'name as Symbol' do
      it 'calls controller method of the same name' do
        controller.class.define_method(:foo) { 'Foo' }
        controller.add_breadcrumb :foo

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_not view.has_selector?('ol li:first-child a')
      end

      context 'name responds to :for_breadcrumb' do
        it 'calls method of the same name on the name object' do
          foo = Class.new do
            def for_breadcrumb
              'Foo'
            end
          end
          controller.class.define_method(:foo) { foo.new }
          controller.add_breadcrumb :foo

          assert view.find('ol li:first-child').has_content?('Foo')
          assert_not view.has_selector?('ol li:first-child a')
        end
      end
    end

    context 'name responds to :for_breadcrumb' do
      it 'calls method of the same name on the name object' do
        foo = Class.new do
          def for_breadcrumb
            'Foo'
          end
        end
        controller.add_breadcrumb foo.new

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_not view.has_selector?('ol li:first-child a')
      end
    end

    context 'name as Symbol with leading @' do
      it 'calls controller instance variable of the same name' do
        controller.instance_variable_set :@foo, 'Foo'
        controller.add_breadcrumb :@foo

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_not view.has_selector?('ol li:first-child a')
      end
    end

    context 'name as Proc' do
      it 'called with helpers as context' do
        controller.instance_variable_set :@foo, 'Foo'
        controller.add_breadcrumb -> { @foo }

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_not view.has_selector?('ol li:first-child a')
      end
    end

    context 'name as Proc; path as Symbol' do
      it 'called with helpers as context' do
        controller.instance_variable_set :@foo, 'Foo'
        controller.add_breadcrumb -> { @foo }, :root

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/', view.find('ol li:first-child a')['href']
      end
    end

    context 'path as Symbol' do
      it 'is passed to url_for' do
        controller.add_breadcrumb 'Foo', :root

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/', view.find('ol li:first-child a')['href']
      end
    end

    context 'path as Symbol which is a controller method' do
      it 'calls controller method of the same name' do
        controller.class.define_method(:foo) { '/foo' }
        controller.add_breadcrumb 'Foo', :foo

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/foo', view.find('ol li:first-child a')['href']
      end
    end

    context 'path as an Array' do
      it 'is passed to url_for' do
        controller.add_breadcrumb 'Foo', [:root]

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/', view.find('ol li:first-child a')['href']
      end
    end

    context 'path as Proc' do
      it 'called with helpers as context' do
        controller.instance_variable_set :@foo, '/'
        controller.add_breadcrumb 'Foo', -> { @foo }

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/', view.find('ol li:first-child a')['href']
      end
    end

    context 'path as Symbol with leading @' do
      it 'calls controller instance variable of the same name' do
        controller.instance_variable_set :@foo, '/foo'
        controller.add_breadcrumb 'Foo', :@foo

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/foo', view.find('ol li:first-child a')['href']
      end
    end

    context 'path containing a Symbol with leading @' do
      it 'calls controller instance variable of the same name' do
        controller.instance_variable_set :@root_path, :root
        controller.add_breadcrumb 'Foo', :@root_path

        assert view.find('ol li:first-child').has_content?('Foo')
        assert_equal '/', view.find('ol li:first-child a')['href']
      end
    end
  end
end
