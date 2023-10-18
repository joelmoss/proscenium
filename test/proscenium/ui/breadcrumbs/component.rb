# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Breadcrumbs::Component do
  extend ViewHelper

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset

    controller.class.include Proscenium::UI::Breadcrumbs::Control
  end

  view -> { subject.new }

  it 'side loads CSS' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/lib/proscenium/ui/breadcrumbs/component.module.css']
  end

  with '@hide_breadcrumbs = true' do
    it 'does not render' do
      controller.instance_variable_set :@hide_breadcrumbs, true
      expect(view.has_selector?('ol')).to be_falsey
    end
  end

  it 'shows home element by default' do
    expect(view.find('ol li:first-child a')['href']).to be == '/'
    expect(view.find('ol li:first-child a').text).to be == 'Home'
  end

  with "home_path: '/foo'" do
    view -> { Proscenium::UI::Breadcrumbs::Component.new home_path: '/foo' }

    it 'uses custom home path' do
      expect(view.find('ol li:first-child a')['href']).to be == '/foo'
    end
  end

  with 'with_home: false' do
    view -> { Proscenium::UI::Breadcrumbs::Component.new with_home: false }

    it 'does not show home element' do
      expect(view.has_selector?('ol li')).to be_falsey
    end
  end

  with 'redefined #home_template' do
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
      expect(view.find('ol li:first-child a')['href']).to be == '/'
      expect(view.find('ol li:first-child a').text).to be == 'Hello'
    end
  end

  describe '#add_breadcrumb' do
    view -> { Proscenium::UI::Breadcrumbs::Component.new with_home: false }

    with 'string name and path' do
      it 'renders breadcrumb as link' do
        controller.add_breadcrumb 'Foo', '/foo'

        expect(view.find('ol li:first-child a').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/foo'
      end
    end

    with 'name only; as string' do
      it 'renders the name as-is, and does not render link' do
        controller.add_breadcrumb 'Foo'

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.has_selector?('ol li:first-child a')).to be_falsey
      end
    end

    with 'name as Symbol' do
      it 'calls controller method of the same name' do
        controller.class.define_method(:foo) { 'Foo' }
        controller.add_breadcrumb :foo

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.has_selector?('ol li:first-child a')).to be_falsey
      end

      with 'name responds to :for_breadcrumb' do
        it 'calls method of the same name on the name object' do
          foo = Class.new do
            def for_breadcrumb
              'Foo'
            end
          end
          controller.class.define_method(:foo) { foo.new }
          controller.add_breadcrumb :foo

          expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
          expect(view.has_selector?('ol li:first-child a')).to be_falsey
        end
      end
    end

    with 'name responds to :for_breadcrumb' do
      it 'calls method of the same name on the name object' do
        foo = Class.new do
          def for_breadcrumb
            'Foo'
          end
        end
        controller.add_breadcrumb foo.new

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.has_selector?('ol li:first-child a')).to be_falsey
      end
    end

    with 'name as Symbol with leading @' do
      it 'calls controller instance variable of the same name' do
        controller.instance_variable_set :@foo, 'Foo'
        controller.add_breadcrumb :@foo

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.has_selector?('ol li:first-child a')).to be_falsey
      end
    end

    with 'name as Proc' do
      it 'called with helpers as context' do
        controller.instance_variable_set :@foo, 'Foo'
        controller.add_breadcrumb -> { @foo }

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.has_selector?('ol li:first-child a')).to be_falsey
      end
    end

    with 'name as Proc; path as Symbol' do
      it 'called with helpers as context' do
        controller.instance_variable_set :@foo, 'Foo'
        controller.add_breadcrumb -> { @foo }, :root

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/'
      end
    end

    with 'path as Symbol' do
      it 'is passed to url_for' do
        controller.add_breadcrumb 'Foo', :root

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/'
      end
    end

    with 'path as Symbol which is a controller method' do
      it 'calls controller method of the same name' do
        controller.class.define_method(:foo) { '/foo' }
        controller.add_breadcrumb 'Foo', :foo

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/foo'
      end
    end

    with 'path as an Array' do
      it 'is passed to url_for' do
        controller.add_breadcrumb 'Foo', [:root]

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/'
      end
    end

    with 'path as Proc' do
      it 'called with helpers as context' do
        controller.instance_variable_set :@foo, '/'
        controller.add_breadcrumb 'Foo', -> { @foo }

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/'
      end
    end

    with 'path as Symbol with leading @' do
      it 'calls controller instance variable of the same name' do
        controller.instance_variable_set :@foo, '/foo'
        controller.add_breadcrumb 'Foo', :@foo

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/foo'
      end
    end

    with 'path containing a Symbol with leading @' do
      it 'calls controller instance variable of the same name' do
        controller.instance_variable_set :@root_path, :root
        controller.add_breadcrumb 'Foo', :@root_path

        expect(view.find('ol li:first-child').has_content?('Foo')).to be_truthy
        expect(view.find('ol li:first-child a')['href']).to be == '/'
      end
    end
  end
end
