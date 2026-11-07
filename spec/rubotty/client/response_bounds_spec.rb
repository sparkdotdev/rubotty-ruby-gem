# frozen_string_literal: true
require 'spec_helper'
require 'stringio'

RSpec.describe 'transport response budgets' do
  def bounded_client(**opts)
    Rubotty::Client.new(token: 'fixture', base_url: 'http://localhost/api', max_response_bytes: 6, **opts)
  end

  [200, 503].each do |status|
    it "stops chunked #{status} responses before retaining bytes above the budget" do
      response = stub_http(status: status)
      received = 0
      allow(response).to receive(:read_body) do |&block|
        %w[abcd efgh never-read].each { |chunk| received += 1; block.call(chunk) }
      end
      expect { bounded_client.ping }.to raise_error(Rubotty::Client::MalformedResponse, /bound/)
      expect(received).to eq(2)
    end
  end

  it 'refuses a declared oversized body before reading it' do
    response = stub_http(headers: { 'Content-Length' => '7' })
    expect(response).not_to receive(:read_body)
    expect { bounded_client.ping }.to raise_error(Rubotty::Client::MalformedResponse, /bound/)
  end

  it 'bounds the upload response independently of streamed request bytes' do
    stub_http(body: '1234567')
    expect { bounded_client.transport.upload('/upload', StringIO.new('file'), filename: 'fixture') }
      .to raise_error(Rubotty::Client::MalformedResponse, /bound/)
  end

  it 'bounds error bodies on an SSE request' do
    stub_sse(%w[abcd efgh never-read], status: 503)
    expect { bounded_client.transport.stream('/stream') {} }
      .to raise_error(Rubotty::Client::MalformedResponse, /bound/)
  end

  it 'allows a healthy stream to outlive the ordinary response byte budget' do
    stub_sse(Array.new(100, "data: cursor: 1\n\n"))
    frames = []
    bounded_client.transport.stream('/stream') { |frame| frames << frame }
    expect(frames.size).to eq(100)
  end

  it 'keeps successful file downloads incremental beyond the ordinary budget' do
    stub_sse(%w[abcd efgh ijkl])
    chunks = []
    bounded_client.transport.download('http://localhost/file') { |chunk| chunks << chunk }
    expect(chunks.join).to eq('abcdefghijkl')
    expect(last_request['Authorization']).to be_nil
  end

  it 'bounds a file download error before yielding any bytes' do
    stub_sse(%w[abcd efgh never-read], status: 503)
    expect { bounded_client.transport.download('http://localhost/file') { raise 'error yielded to download' } }
      .to raise_error(Rubotty::Client::MalformedResponse, /bound/)
  end

  it 'bounds an incomplete stream frame' do
    stub_sse(['data: ', 'unfinished'])
    expect { bounded_client(max_frame_bytes: 8).transport.stream('/stream') {} }
      .to raise_error(Rubotty::Client::MalformedResponse, /frame.*bound/)
  end
end

RSpec.describe 'native identity grant fields' do
  it 'forwards native_id in both viewer grant surfaces and retains grant state' do
    client = Rubotty::Client.new(token: 'fixture', base_url: 'http://localhost/api')
    stub_http(status: 201, body: "id: 1\nnative_id: \"9001\"\nrequires_regrant: false\n")
    row = client.admin_grant_viewer(adapter: 'telegram', handle: 'ada', native_id: '9001')
    expect(URI.decode_www_form(last_request.body).to_h['native_id']).to eq('9001')
    expect(row.native_id).to eq('9001')
    expect(row.requires_regrant).to be(false)
    row = client.grant_community_viewer('fixture', adapter: 'telegram', handle: 'ada', native_id: '9001')
    expect(URI.decode_www_form(last_request.body).to_h['native_id']).to eq('9001')
    expect(row.native_id).to eq('9001')
    legacy = Rubotty::Client::Models::Viewer.from_h('native_id' => nil, 'requires_regrant' => true)
    expect(legacy.native_id).to be_nil
    expect(legacy.requires_regrant).to be(true)
  end
end
