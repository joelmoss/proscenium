# frozen_string_literal: true

class Phlex::SideLoadControllerTest < ActionDispatch::IntegrationTest
  setup do
    Proscenium.config.cache_query_string = false
    Proscenium::Importer.reset
  end

  test 'Side load from controller' do
    get '/phlex/basic'

    assert_matches_snapshot response.body
  end
end
