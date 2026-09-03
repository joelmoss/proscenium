# frozen_string_literal: true

# Server rendered JavaScript. Proscenium marks `*.rjs` external, so the browser fetches this
# directly - which is also how the Bun test harness reaches it, via `Rails.application.call`.
class RjsController < ApplicationController
  # Required for any action serving JavaScript over a plain GET. Without it Rails raises
  # ActionController::InvalidCrossOriginRequest, in the browser as well as under test.
  skip_forgery_protection

  def constants
    render js: "export const GREETING = #{params.fetch(:greeting, 'hello').to_json};\n"
  end

  def boom
    raise 'rjs blew up'
  end
end
