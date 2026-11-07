# frozen_string_literal: true

require "spec_helper"

# The status codes this API actually uses, and what each one means here. The
# 403/404 split is the part worth holding still: 403 says "this class of route
# is not yours", 404 says either "no such thing" or "not yours to see" with no
# way to tell which.
RSpec.describe Rubotty::Client do
  let(:client) { described_class.new(token: "k3y", base_url: "https://example.test/api") }

  def answer(status, error: nil, headers: {})
    stub_http(status: status, body: error.nil? ? "" : YAMLCamel.dump({ "error" => error }), headers: headers)
  end

  it "raises Unauthorized on 401, carrying the API's own sentence" do
    answer(401, error: "invalid or revoked API key")

    expect { client.community("sample") }
      .to raise_error(Rubotty::Client::Unauthorized, "invalid or revoked API key") { |e| expect(e.status).to eq(401) }
  end

  it "raises Forbidden on 403, which only ever means a developer key hit an admin route" do
    answer(403, error: "administrator scope required")

    expect { client.admin_communities }.to raise_error(Rubotty::Client::Forbidden, /administrator scope required/)
  end

  it "raises NotFound on 404, whether the thing is missing or simply not visible to this key" do
    answer(404, error: "not found")

    expect { client.room("someone-elses-community", "general") }.to raise_error(Rubotty::Client::NotFound)
  end

  it "raises BadRequest on 400" do
    answer(400, error: "source must be web, bot, or all")

    expect { client.admin_debug_info(source: "banana") }
      .to raise_error(Rubotty::Client::BadRequest, /web, bot, or all/)
  end

  it "raises ValidationFailed on 422, with the refusal the control plane gave" do
    answer(422, error: "unknown feature: wordfilter")

    expect { client.set_community_feature("sample", "wordfilter", enabled: true) }
      .to raise_error(Rubotty::Client::ValidationFailed, "unknown feature: wordfilter")
  end

  it "raises RateLimited on 429 and reads Retry-After" do
    answer(429, error: "rate limit exceeded", headers: { "Retry-After" => "30" })

    expect { client.community("sample") }.to raise_error(Rubotty::Client::RateLimited) do |error|
      expect(error.retry_after).to eq(30)
      expect(error.status).to eq(429)
    end
  end

  it "leaves retry_after nil when the header is absent or is an HTTP date" do
    answer(429, error: "rate limit exceeded")
    expect { client.community("sample") }.to raise_error(Rubotty::Client::RateLimited) { |e| expect(e.retry_after).to be_nil }

    answer(429, error: "rate limit exceeded", headers: { "Retry-After" => "Wed, 21 Oct 2026 07:28:00 GMT" })
    expect { client.community("sample") }.to raise_error(Rubotty::Client::RateLimited) { |e| expect(e.retry_after).to be_nil }
  end

  it "falls back to the plain ApiError for a status the API does not define" do
    answer(500, error: "boom")

    expect { client.community("sample") }.to raise_error(Rubotty::Client::ApiError) do |error|
      expect(error.status).to eq(500)
      expect(error.class).to eq(Rubotty::Client::ApiError)
    end
  end

  it "still names the status when the body came from a proxy rather than the API" do
    stub_http(status: 502, body: "<html><body>502 Bad Gateway</body></html>")

    expect { client.community("sample") }.to raise_error(Rubotty::Client::ApiError, /502/) do |error|
      expect(error.body).to include("Bad Gateway")
    end
  end

  it "keeps the raw body on the exception for a failure worth logging in full" do
    answer(422, error: "room selector matched nothing")

    expect { client.set_room_feature("sample", "nope", "word_filter", enabled: true) }
      .to raise_error(Rubotty::Client::ValidationFailed) { |e| expect(e.body).to include("room selector") }
  end

  it "wraps a socket failure as ConnectionError" do
    stub_http_failure

    expect { client.community("sample") }
      .to raise_error(Rubotty::Client::ConnectionError, /could not reach example.test/)
  end

  it "puts everything under one base error" do
    [Rubotty::Client::ApiError, Rubotty::Client::Unauthorized, Rubotty::Client::Forbidden,
     Rubotty::Client::NotFound, Rubotty::Client::BadRequest, Rubotty::Client::ValidationFailed,
     Rubotty::Client::RateLimited, Rubotty::Client::ConnectionError,
     Rubotty::Client::MalformedResponse].each do |klass|
      expect(klass.ancestors).to include(Rubotty::Client::Error)
    end
  end
end
