# frozen_string_literal: true

require 'view_helper'

describe Proscenium::UI::Form::Component do
  include TestHelper
  extend ViewHelper

  let(:user) { User.new }
  view -> { subject.new user }

  it 'side loads CSS' do
    view
    imports = Proscenium::Importer.imported.keys

    expect(imports).to be == ['/proscenium/ui/form/component.module.css']
  end

  it 'has an action attribute' do
    expect(view.find('form')[:action]).to be == '/users'
  end

  with 'default method' do
    it 'has a default method attribute' do
      expect(view.find('form')[:method]).to be == 'post'
    end

    it 'does not have a hidden _method field' do
      expect(view.has_field?('_method', type: :hidden)).to be == false
    end
  end

  with 'method: :get' do
    view -> { subject.new(user, method: :get) }

    it 'has a method attribute' do
      expect(view.find('form')[:method]).to be == 'get'
    end

    it 'does not have a hidden _method field' do
      expect(view.has_field?('_method', type: :hidden)).to be == false
    end
  end

  with 'method: :patch' do
    view -> { subject.new(user, method: :patch) }

    it 'form[method] == post' do
      expect(view.find('form')[:method]).to be == 'post'
    end

    it 'has a hidden _method field' do
      expect(view.find('input[name=_method]', visible: :hidden)[:value]).to be == 'patch'
    end
  end

  with 'persisted model record' do
    let(:user) { User.create! }
    view -> { subject.new(user) }

    it 'has a hidden _method field' do
      expect(view.find('input[name=_method]', visible: :hidden)[:value]).to be == 'patch'
    end
  end

  it 'has an authenticity_token field' do
    expect(view.has_field?('authenticity_token', type: :hidden)).to be == true
  end

  with ':url' do
    view -> { subject.new(user, url: '/') }

    it 'sets form action to URL' do
      expect(view.find('form')[:action]).to be == '/'
    end
  end

  describe '#submit' do
    view -> { Proscenium::UI::Form::Component.new(user) } do |f|
      f.submit 'Save'
    end

    it 'has a submit button' do
      expect(view.has_button?('Save')).to be == true
    end
  end
end
