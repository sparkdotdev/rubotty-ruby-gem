# frozen_string_literal: true

require "net/http"

# A fake HTTP connection injected through Net::HTTP.start, the same seam the
# main repo's specs use for BotNudge and BotLogsClient. Nothing here builds a
# server or opens a socket: the client's real request object is captured on
# the way past, so a spec can assert what was actually sent as well as what
# the client made of the answer.
module FakeHttp
  # @param status [Integer] the response code the fake answers with
  # @param body [String] the response body, verbatim
  # @param headers [Hash] response headers
  # @return [Net::HTTPResponse] the response the fake will return
  def stub_http(status: 200, body: "", headers: {})
    response = http_response(status: status, body: body, headers: headers)
    @http_requests = []
    @http_connections = []

    connection = instance_double(Net::HTTP)
    allow(response).to receive(:read_body) { |&block| block ? block.call(body) : body }
    allow(connection).to receive(:request) do |request, &block|
      @http_requests << request
      block ? block.call(response) : response
    end

    allow(Net::HTTP).to receive(:start) do |host, port, **kwargs, &block|
      @http_connections << { host: host, port: port }.merge(kwargs)
      block.call(connection)
    end

    response
  end

  # Make Net::HTTP.start itself blow up, for the connection-failure path.
  def stub_http_failure(error = Errno::ECONNREFUSED)
    allow(Net::HTTP).to receive(:start).and_raise(error)
  end

  # The streaming shape: Net::HTTP#request called WITH a block, and the
  # response read through #read_body chunk by chunk rather than in one piece.
  #
  # +chunks+ is delivered exactly as given, so a spec can split a frame across
  # a boundary on purpose. That case is the reason the client buffers instead
  # of treating each chunk as a frame, and it is not something a fake that
  # always hands over one tidy frame at a time would ever exercise.
  def stub_sse(chunks, status: 200)
    @http_requests = []
    @http_connections = []
    whole = chunks.join
    response = http_response(status: status, body: whole, headers: { "Content-Type" => "text/event-stream" })
    # `whole` rather than `response.body`, because Net::HTTPResponse#body is
    # implemented as a call to #read_body, and reaching for it from inside this
    # stub would call the stub again and never come back.
    allow(response).to receive(:read_body) do |&block|
      block.nil? ? whole : chunks.each { |chunk| block.call(chunk) }
    end

    connection = instance_double(Net::HTTP)
    allow(connection).to receive(:request) do |request, &block|
      @http_requests << request
      block.nil? ? response : block.call(response)
    end

    allow(Net::HTTP).to receive(:start) do |host, port, **kwargs, &block|
      @http_connections << { host: host, port: port }.merge(kwargs)
      block.call(connection)
    end

    response
  end

  def last_request = @http_requests.last

  def last_connection = @http_connections.last

  def request_count = @http_requests.size

  private

  # A real Net::HTTPResponse of the right subclass for the code, so the
  # client's `case response when Net::HTTPSuccess` checks exercise the same
  # class hierarchy they will meet in production. @read is set because a
  # response built by hand has never been read off a socket, and #body
  # returns nil until it has.
  def http_response(status:, body:, headers: {})
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s)
    response = klass.new("1.1", status.to_s, klass.name.split("::").last)
    headers.each { |name, value| response[name] = value }
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end
end
