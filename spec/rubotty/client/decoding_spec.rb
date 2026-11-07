# frozen_string_literal: true

require "spec_helper"

# The YAML decode, which is the reason this gem exists rather than a generated
# one. A response body is untrusted input: anything that would turn it into
# Ruby objects, expand an alias bomb, or quietly hand back something that is
# not a mapping has to fail instead.
RSpec.describe Rubotty::Client do
  let(:client) { described_class.new(token: "k3y", base_url: "https://example.test/api") }

  # Instantiated only if the loader is talked into building a Ruby object,
  # which is exactly what must never happen.
  class DecodeCanary
    def self.built = @built ||= 0

    def initialize = self.class.instance_variable_set(:@built, self.class.built + 1)
  end

  it "builds a model whose accessors read the string keys the API sent" do
    stub_http(body: YAMLCamel.dump({ "slug" => "sample", "name" => "SAMPLE", "status" => "active" }))

    community = client.community("sample")
    expect(community).to be_a(Rubotty::Client::Models::Community)
    expect([community.slug, community.name, community.status]).to eq(["sample", "SAMPLE", "active"])
  end

  it "keeps a genuinely free-form field, config among them, as a plain Hash rather than a model" do
    stub_http(body: YAMLCamel.dump({ "scope" => "room", "feature" => "word_filter", "enabled" => true,
                                "config" => { "action" => "delete", "words" => %w[a b] } }))

    expect(client.room_feature("sample", "general", "word_filter").config)
      .to eq("action" => "delete", "words" => %w[a b])
  end

  # The reader builds core schema types only, so a tag naming a class is read
  # past and the mapping underneath it comes back as plain data. The class is
  # never reached, which is the property worth holding: there is no permitted
  # classes list to get wrong here, and no document that can name a constructor.
  it "never builds a Ruby class a body names" do
    stub_http(body: "--- !ruby/object:DecodeCanary\nboom: 1\n")

    expect(client.community("sample")).to be_a(Rubotty::Client::Models::Community)
    expect(DecodeCanary.built).to eq(0)
  end

  it "expands an ordinary alias, which is what a spec-correct server may send" do
    body = <<~YAML
      ---
      name: &shared SAMPLE
      slug: sample
      status: *shared
    YAML
    stub_http(body: body)

    community = client.community("sample")
    expect(community.name).to eq("SAMPLE")
    expect(community.status).to eq("SAMPLE")
  end

  # Alias expansion is bounded rather than switched off, so the small body that
  # expands into an enormous one is still refused, and an honest one still works.
  it "refuses a body whose aliases expand without bound" do
    levels = %w[b c d e f g h i]
    bomb = +"a: &a [x,x,x,x,x,x,x,x,x]\n"
    levels.each_with_index do |key, index|
      previous = index.zero? ? "a" : levels[index - 1]
      bomb << "#{key}: &#{key} [#{(["*#{previous}"] * 9).join(",")}]\n"
    end
    stub_http(body: bomb)

    expect { client.community("sample") }.to raise_error(Rubotty::Client::MalformedResponse)
  end

  it "refuses a body that is not a mapping" do
    stub_http(body: YAMLCamel.dump(%w[one two]))

    expect { client.community("sample") }.to raise_error(Rubotty::Client::MalformedResponse, /got Array/)
  end

  it "builds a model with every field nil from an empty body, rather than an empty mapping" do
    stub_http(body: "")

    community = client.community("sample")
    expect(community).to be_a(Rubotty::Client::Models::Community)
    expect(community.slug).to be_nil
  end

  # YAML 1.2's core schema has no timestamp type, so a date-shaped scalar is a
  # string and stays one. It used to load as a Date and be refused for being a
  # class. The API stringifies its timestamps before writing them either way.
  it "reads an unquoted date as the string it is written as" do
    stub_http(body: "---\ncreated_at: 2026-07-01\n")

    expect(client.community("sample").created_at).to eq("2026-07-01")
  end

  it "returns a plain true from every route that answers 204" do
    [[:reset_room_feature, "sample", "general", "word_filter"],
     [:admin_archive_script, "sample", 5],
     [:admin_delete_script_endpoint, "sample", 2]].each do |name, *args|
      stub_http(status: 204, body: "")

      expect(client.public_send(name, *args)).to be(true)
      expect(last_request.method).to eq("DELETE")
    end
  end

  it "hands back the liveness probe's text body without decoding it" do
    stub_http(body: "ok\n", headers: { "Content-Type" => "text/plain" })

    expect(client.ping).to eq("ok\n")
  end

  it "raises when a list route's envelope key is missing" do
    stub_http(body: YAMLCamel.dump({ "chanels" => [] }))

    expect { client.channels("sample") }.to raise_error(Rubotty::Client::MalformedResponse, /"channels"/)
  end
end
