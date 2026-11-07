# frozen_string_literal: true

require "spec_helper"

# Construction and the shape of the request that goes out: headers, the mount
# path, segment escaping and how a write body gets encoded. What comes back is
# covered in decoding_spec.rb, and what happens when it fails in errors_spec.rb.
RSpec.describe Rubotty::Client do
  let(:client) { described_class.new(token: "k3y", base_url: "https://example.test/api") }

  describe "construction" do
    it "requires a token" do
      expect { described_class.new(token: nil) }.to raise_error(ArgumentError, /token is required/)
      expect { described_class.new(token: "   ") }.to raise_error(ArgumentError, /token is required/)
    end

    it "requires an explicit destination" do
      expect { described_class.new(token: "k") }.to raise_error(ArgumentError, /base_url is required/)
    end

    it "refuses a base URL that is not http or https" do
      expect { described_class.new(token: "k", base_url: "example.test/api") }
        .to raise_error(ArgumentError, /http or https/)
    end
  end

  describe "the request it sends" do
    it "carries the bearer token, asks for YAML, and names itself" do
      stub_http(body: "--- {}\n")
      client.community("sample")

      expect(last_request["Authorization"]).to eq("Bearer k3y")
      expect(last_request["Accept"]).to eq("application/yaml")
      expect(last_request["User-Agent"]).to eq("rubotty-client/#{Rubotty::Client::VERSION}")
    end

    it "connects over TLS to the host in the base URL" do
      stub_http(body: "--- {}\n")
      client.community("sample")

      expect(last_connection).to include(host: "example.test", port: 443, use_ssl: true)
    end

    it "keeps the mount path from the base URL in front of every route" do
      stub_http(body: "--- {}\n")
      client.community("sample")

      expect(last_request.path).to eq("/api/communities/sample")
    end

    it "tolerates a base URL with a trailing slash or no path at all" do
      stub_http(body: "--- {}\n")
      described_class.new(token: "k", base_url: "http://localhost:9292/api/").community("sample")
      expect(last_request.path).to eq("/api/communities/sample")

      stub_http(body: "--- {}\n")
      described_class.new(token: "k", base_url: "http://localhost:9292").community("sample")
      expect(last_request.path).to eq("/communities/sample")
      expect(last_connection).to include(host: "localhost", port: 9292, use_ssl: false)
    end

    it "percent-encodes a path segment, spaces and slashes included" do
      stub_http(body: "--- {}\n")
      client.room("sample", "off topic/2")

      expect(last_request.path).to eq("/api/communities/sample/rooms/off%20topic%2F2")
    end

    it "encodes an accented label a byte at a time" do
      stub_http(body: "--- {}\n")
      client.fluxer_instance("sample", "café")

      expect(last_request.path).to eq("/api/communities/sample/fluxer-instances/caf%C3%A9")
    end

    it "sends only the query params that were given" do
      stub_http(body: YAMLCamel.dump({ "entries" => [] }))
      client.admin_debug_logs(source: "all", limit: 50)

      expect(last_request.path).to eq("/api/admin/debug/logs?source=all&limit=50")
    end

    it "sends no query string when nothing was given" do
      stub_http(body: "--- {}\n")
      client.admin_debug_info

      expect(last_request.path).to eq("/api/admin/debug/info")
    end
  end

  describe "write bodies" do
    it "form-encodes a flat body" do
      stub_http(body: YAMLCamel.dump({ "feature" => "word_filter", "enabled" => true }))
      client.set_community_feature("sample", "word_filter", enabled: true)

      expect(last_request["Content-Type"]).to eq("application/x-www-form-urlencoded")
      expect(last_request.body).to eq("enabled=true")
      expect(last_request.method).to eq("PATCH")
    end

    it "sends YAML when the body nests, which is what the config mapping does" do
      stub_http(body: YAMLCamel.dump({ "feature" => "word_filter", "enabled" => true }))
      client.set_community_feature("sample", "word_filter", enabled: true,
                                                          config: { "action" => "delete", "threshold" => 3 })

      expect(last_request["Content-Type"]).to eq("application/yaml")
      expect(YAMLCamel.load(last_request.body))
        .to eq("enabled" => true, "config" => { "action" => "delete", "threshold" => 3 })
    end

    it "turns symbols into strings on the way out, since the API refuses a symbol too" do
      stub_http(body: "--- {}\n")
      client.set_room_feature("sample", "general", "word_filter", config: { action: :delete })

      expect(YAMLCamel.load(last_request.body))
        .to eq("config" => { "action" => "delete" })
    end

    it "refuses a feature write that would change nothing" do
      expect { client.set_community_feature("sample", "word_filter") }
        .to raise_error(ArgumentError, /enabled:, config:, or both/)
    end
  end
end
