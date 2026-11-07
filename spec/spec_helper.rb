# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "rubotty/client"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include FakeHttp

  # The same rule the main repo's suite holds to: no spec may touch the
  # network. Anything reaching for a socket is a bug in the spec, so it fails
  # loudly here rather than timing out against whatever is listening.
  config.before do
    allow(Net::HTTP).to receive(:start) do
      raise "a spec attempted a real HTTP request. Use stub_http to inject a fake connection."
    end
  end
end
