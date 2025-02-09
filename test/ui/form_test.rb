# frozen_string_literal: true

require 'test_helper'

class Proscenium::UI::FormTest < ActiveSupport::TestCase
  extend ViewHelper

  let(:subject) { Proscenium::UI::Form }
  let(:user) { User.new }
  view -> { subject.new user }

  it 'side loads CSS' do
    view
    imports = Proscenium::Importer.imported.keys

    assert_equal ['/proscenium/form.css'], imports
  end

  it 'has an action attribute' do
    assert_equal '/users', view.find('form')[:action]
  end

  with 'default method' do
    it 'has a default method attribute' do
      assert_equal 'post', view.find('form')[:method]
    end

    it 'does not have a hidden _method field' do
      assert_not view.has_field?('_method', type: :hidden)
    end
  end

  with 'method: :get' do
    view -> { subject.new(user, method: :get) }

    it 'has a method attribute' do
      assert_equal 'get', view.find('form')[:method]
    end

    it 'does not have a hidden _method field' do
      assert_not view.has_field?('_method', type: :hidden)
    end
  end

  with 'method: :patch' do
    view -> { subject.new(user, method: :patch) }

    it 'form[method] == post' do
      assert_equal 'post', view.find('form')[:method]
    end

    it 'has a hidden _method field' do
      assert_equal 'patch', view.find('input[name=_method]', visible: :hidden)[:value]
    end
  end

  with 'persisted model record' do
    let(:user) { User.create! }
    view -> { subject.new(user) }

    it 'has a hidden _method field' do
      assert_equal 'patch', view.find('input[name=_method]', visible: :hidden)[:value]
    end
  end

  it 'has an authenticity_token field' do
    assert view.has_field?('authenticity_token', type: :hidden)
  end

  with ':action' do
    view -> { subject.new(user, action: '/') }

    it 'sets form action to URL' do
      assert_equal '/', view.find('form')[:action]
    end
  end

  describe '#submit' do
    view -> { subject.new(user) } do |f|
      f.submit 'Save'
    end

    it 'has a submit button' do
      assert view.has_button?('Save')
    end
  end
end
