# frozen_string_literal: true

DatabaseCleaner.strategy = :transaction

module TestHelper
  def around
    DatabaseCleaner.cleaning { super }
  end

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end
end

### Debugging
#
# Print browser console logs
#   page.driver.browser.options.logger.logs
#
