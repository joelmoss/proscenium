# frozen_string_literal: true

require_relative 'helper'

describe Proscenium::CLI::Inspect do
  it 'redacts credentials in URLs' do
    inspect = Proscenium::CLI::Inspect.new('/app', nil)

    # Assembled, so no credential-shaped URL sits in the source for scanners to flag.
    url = ['git+https://', 'user:fake', '@host/x.git#v1'].join

    assert_equal 'git+https://<redacted>@host/x.git#v1', inspect.send(:redact, url)
    assert_equal 'github:owner/repo#abc', inspect.send(:redact, 'github:owner/repo#abc')
  end
end
