# frozen_string_literal: true

require 'test_helper'

class Proscenium::SideLoadTest < ActiveSupport::TestCase
  context 'side load disabled' do
    before do
      Proscenium.config.side_load = false
    end

    it 'does not side load layout and view' do
      BarePagesController.render :home

      assert_nil Proscenium::Importer.imported
    end

    it 'does not side load partial' do
      BarePagesController.render :sideloadpartial

      assert_nil Proscenium::Importer.imported
    end
  end

  it 'side loads layout and view' do
    BarePagesController.render :home

    assert_equal({
                   '/app/views/layouts/bare.js' => {},
                   '/app/views/layouts/bare.css' => {},
                   '/app/views/bare_pages/home.js' => {},
                   '/app/views/bare_pages/home.css' => {}
                 }, Proscenium::Importer.imported)
  end

  it 'side loads variant' do
    skip 'fixme'
    pp PagesController.new.request
    pp PagesController.render :variant
  end

  it 'side loads partial' do
    BarePagesController.render :sideloadpartial

    assert_equal({
                   '/app/views/layouts/bare.js' => {},
                   '/app/views/layouts/bare.css' => {},
                   '/app/views/pages/_side.js' => {},
                   '/app/views/pages/_side_layout.css' => {}
                 }, Proscenium::Importer.imported)
  end

  # A partial's `sideload_assets` value belongs to that one render. It used to be kept per template
  # for the whole request, so a second render of the partial that did not set it inherited `false`.
  it 'scopes a partial sideload_assets value to its own render' do
    BarePagesController.render :suppress_then_render

    assert Proscenium::Importer.imported?('/app/views/pages/_suppressible.js')
  end

  # Rendering happens before Proscenium::Helper is included into views (it is included in
  # `after_initialize`), e.g. from an initializer. The view then has no override store at all.
  it 'side loads a template rendered by a view without Proscenium::Helper' do
    controller = Struct.new(:sideload_assets_options).new(nil)
    view = Struct.new(:controller).new(controller)
    tpl = Struct.new(:identifier).new(Rails.root.join('app/views/bare_pages/home.html.erb').to_s)

    assert_equal :rendered, Proscenium::SideLoad.sideload_templates(view, [tpl]) { :rendered }
    assert Proscenium::Importer.imported?('/app/views/bare_pages/home.js')
  end

  # Pins documented behaviour: a fragment cache hit skips the block, so a `sideload_assets` call
  # inside it does not run, and the template's assets are side loaded.
  it 'ignores a sideload_assets call inside a cache block on a cache hit' do
    was_caching = BarePagesController.perform_caching
    was_store = BarePagesController.cache_store
    BarePagesController.perform_caching = true
    BarePagesController.cache_store = ActiveSupport::Cache::MemoryStore.new

    BarePagesController.render :cached
    assert_not Proscenium::Importer.imported?('/app/views/bare_pages/cached.js')

    Proscenium::Importer.reset
    BarePagesController.render :cached
    assert Proscenium::Importer.imported?('/app/views/bare_pages/cached.js')
  ensure
    BarePagesController.perform_caching = was_caching
    BarePagesController.cache_store = was_store
  end

  # `false` is a valid layout, and means none. A false layout used to be skipped by a truthiness
  # check; it must not reach the side loader as a template.
  it 'renders a template and a partial given a false layout' do
    BarePagesController.render inline: <<~ERB
      <%= render template: 'bare_pages/home', layout: false %>
      <%= render partial: 'pages/side', layout: false %>
    ERB

    assert Proscenium::Importer.imported?('/app/views/bare_pages/home.js')
    assert Proscenium::Importer.imported?('/app/views/pages/_side.js')
  end

  # A template rendered as its own layout must still get the outer render's value back.
  it 'restores the stored value of a template that is its own layout' do
    tpl = Struct.new(:identifier).new('/no/such/file.html.erb')
    store = { tpl.identifier => :outer }
    view = Struct.new(:controller, :proscenium_sideload_assets_options)
                 .new(Struct.new(:sideload_assets_options).new(nil), store)

    Proscenium::SideLoad.sideload_templates(view, [tpl, tpl]) { nil }

    assert_equal({ tpl.identifier => :outer }, store)
  end

  # Options are often built with indifferent access, e.g. from Rails config.
  it 'honours options with indifferent access' do
    BarePagesController.sideload_assets({ css: false, js: proc { false } }.with_indifferent_access)
    BarePagesController.render :home

    assert_nil Proscenium::Importer.imported
  ensure
    BarePagesController.sideload_assets nil
  end

  describe '.merge_options' do
    let(:receiver) { Struct.new(:flag).new(:from_receiver) }

    it 'is empty for nil base and override' do
      assert_equal({}, Proscenium::SideLoad.merge_options(nil, nil, receiver))
    end

    it 'expands a non-Hash base to both css and js' do
      assert_equal({ js: false, css: false },
                   Proscenium::SideLoad.merge_options(false, nil, receiver))
    end

    it 'deep merges a Hash override over a Hash base' do
      result = Proscenium::SideLoad.merge_options({ css: { class: :foo }, js: false },
                                                  { css: { data: { a: 1 } } }, receiver)

      assert_equal({ css: { class: :foo, data: { a: 1 } }, js: false }, result)
    end

    # Keys are normalised before merging, so an indifferent-access override merges into a
    # symbol-keyed base instead of sitting beside it and then replacing it.
    it 'deep merges an indifferent-access override over a symbol-keyed base' do
      base = { js: { integrity: 'sha384-x', defer: true } }
      override = { js: { data: { widget: 'menu' } } }.with_indifferent_access

      assert_equal({ js: { integrity: 'sha384-x', defer: true, data: { widget: 'menu' } } },
                   Proscenium::SideLoad.merge_options(base, override, receiver))
    end

    # Nested keys too: the stylesheet tag adds `data: {}` by symbol, which would replace a string
    # `'data'` key.
    it 'symbolizes nested keys' do
      result = Proscenium::SideLoad.merge_options({ css: { data: { foo: 'bar' } } }
                                                    .with_indifferent_access, nil, receiver)

      assert_equal({ css: { data: { foo: 'bar' } } }, result)
    end

    it 'replaces the base with a non-Hash override' do
      assert_equal({ js: true, css: true },
                   Proscenium::SideLoad.merge_options({ css: { class: :foo } }, true, receiver))
    end

    it 'evaluates procs against the receiver' do
      result = Proscenium::SideLoad.merge_options({ css: proc { flag } }, nil, receiver)

      assert_equal :from_receiver, result[:css]
    end

    it 'modifies neither input, and shares no hash with them' do
      base = { css: { data: { a: 1 } }, js: proc { { defer: true } } }.freeze
      override = { css: { class: :foo } }.freeze

      result = Proscenium::SideLoad.merge_options(base, override, receiver)
      result[:css][:data][:b] = 2
      result[:js][:async] = true

      assert_equal({ a: 1 }, base[:css][:data])
      assert_kind_of Proc, base[:js]
      assert_equal({ class: :foo }, override[:css])
    end

    # A proc returning a shared hash must not hand that hash out either.
    it 'copies a hash returned by a proc' do
      shared = { defer: true }
      result = Proscenium::SideLoad.merge_options({ js: proc { shared } }, nil, receiver)
      result[:js][:async] = true

      assert_equal({ defer: true }, shared)
    end

    # Only Hash containers are copied. `dup` on an ActiveRecord model returns a new, unsaved
    # record with no id, so a `data:` value holding one would render with `"id":null`.
    it 'passes values other than hashes through untouched' do
      record = Object.new
      result = Proscenium::SideLoad.merge_options({ js: { data: { widget: record } } }, nil,
                                                  receiver)

      assert_same record, result[:js][:data][:widget]
    end
  end

  # proscenium-phlex calls this with the controller's class attribute as `options`.
  describe '.sideload_inheritance_chain' do
    it 'modifies neither the given options nor the object options' do
      options = { css: proc { false }, js: { defer: true } }
      obj = Struct.new(:sideload_assets_options).new({ js: proc { { async: true } } })

      Proscenium::SideLoad.sideload_inheritance_chain(obj, options)

      assert_kind_of Proc, options[:css]
      assert_equal({ defer: true }, options[:js])
      assert_kind_of Proc, obj.sideload_assets_options[:js]
    end
  end
end
