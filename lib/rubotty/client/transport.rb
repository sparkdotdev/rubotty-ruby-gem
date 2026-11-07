# frozen_string_literal: true

require "net/http"
require "uri"
require "yamlcamel"

module Rubotty
  class Client
    # The HTTP half of the client: one request, the YAML decode, and the
    # mapping from a status code to an exception class. It lives apart from
    # {Client} so that the operation list there stays a list of routes with
    # nothing else mixed into it.
    #
    # Every call opens its own connection. There is no pool and no keep-alive
    # because this API gets driven by scripts making a handful of requests at
    # a time, where a reconnect costs less than the shared state a pooled
    # transport would have to own and invalidate.
    class Transport
      DEFAULT_OPEN_TIMEOUT = 5
      DEFAULT_READ_TIMEOUT = 15
      DEFAULT_MAX_RESPONSE_BYTES = 16 * 1024 * 1024
      DEFAULT_MAX_FRAME_BYTES = 16 * 1024 * 1024

      # What an uploaded part is labelled when the caller names no type. The
      # far end stores whatever it is told, so an honest "unknown bytes" is
      # better than guessing from the file extension and being wrong.
      DEFAULT_UPLOAD_TYPE = "application/octet-stream"

      VERBS = {
        get: Net::HTTP::Get,
        patch: Net::HTTP::Patch,
        post: Net::HTTP::Post,
        put: Net::HTTP::Put,
        delete: Net::HTTP::Delete
      }.freeze

      STATUS_ERRORS = {
        400 => BadRequest,
        401 => Unauthorized,
        403 => Forbidden,
        404 => NotFound,
        422 => ValidationFailed,
        429 => RateLimited
      }.freeze

      # Everything RFC 3986 calls unreserved. Anything else in a path segment
      # gets percent-encoded by {.escape_segment}.
      RESERVED_IN_SEGMENT = /[^A-Za-z0-9\-._~]/

      # Percent-encode one path segment. URI.encode_www_form_component is the
      # wrong tool here: it encodes a space as "+", which a path reads as a
      # literal plus, and this matters because a room_key, a Fluxer label and
      # an IRC network name are all operator-authored text that can hold
      # spaces, slashes and accents.
      def self.escape_segment(value)
        value.to_s.gsub(RESERVED_IN_SEGMENT) do |char|
          char.bytes.map { |byte| format("%%%02X", byte) }.join
        end
      end

      attr_reader :base_url

      # @param base_url [String] the API root, mount path included
      # @param token [String] the bearer key
      # @param open_timeout [Numeric]
      # @param read_timeout [Numeric]
      # @param user_agent [String]
      def initialize(base_url:, token:, open_timeout: DEFAULT_OPEN_TIMEOUT,
                     read_timeout: DEFAULT_READ_TIMEOUT, user_agent: nil,
                     max_response_bytes: DEFAULT_MAX_RESPONSE_BYTES, max_frame_bytes: DEFAULT_MAX_FRAME_BYTES)
        unless [max_response_bytes, max_frame_bytes].all? { |limit| limit.is_a?(Integer) && limit.positive? }
          raise ArgumentError, "response and frame bounds must be positive integers"
        end
        @max_response_bytes = max_response_bytes
        @max_frame_bytes = max_frame_bytes
        @base_url = base_url.to_s
        raise ArgumentError, "an explicit base_url is required" if @base_url.empty?

        @root = URI.parse(@base_url)
        raise ArgumentError, "base_url must be an http or https URL, got #{@base_url.inspect}" unless @root.is_a?(URI::HTTP)

        if @root.host.to_s.empty? || @root.userinfo || @root.query || @root.fragment
          raise ArgumentError, "base_url must name a host without credentials, query or fragment"
        end
        if @root.scheme != "https" && !%w[localhost 127.0.0.1 ::1 [::1]].include?(@root.host)
          raise ArgumentError, "base_url requires HTTPS except for loopback development"
        end

        # The API is mounted under a path ("/api" in production), so a request
        # path is appended to that rather than replacing it. URI.join would
        # replace it, which is the whole reason this is done by hand.
        @mount = @root.path.chomp("/")
        @token = token
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @user_agent = user_agent || "rubotty-client/#{VERSION}"
      end

      def get(path, query: nil, raw: false) = request(:get, path, query: query, raw: raw)

      def patch(path, body) = request(:patch, path, body: body)

      def post(path, body = nil) = request(:post, path, body: body)

      def put(path, body) = request(:put, path, body: body)

      # +body+ is optional because most DELETEs in this API address a
      # resource by path alone, but a handful, a word filter entry and a
      # bridge reaction among them, need a body to say which of several
      # things attached to the path is being removed.
      def delete(path, body = nil) = request(:delete, path, body: body)

      # POST a file as multipart, which is the one request in this API that is
      # not form-encoded or YAML. Bytes cannot ride a YAML mapping without
      # base64, and base64 would inflate the request by a third and hold the
      # whole file in memory at both ends.
      #
      # +io+ is read straight onto the socket as the request is written, so a
      # file far larger than this process's memory uploads without ever being
      # held. That is Net::HTTP's own doing: set_form with multipart streams an
      # IO part rather than building the body first.
      #
      # @param io [#read]
      # @param filename [String] the name recorded at the far end
      # @param content_type [String, nil]
      # @param fields [Hash] any other form fields to send alongside
      def upload(path, io, filename:, content_type: nil, fields: {})
        uri = url_for(path, nil)
        request = build_request(:post, uri, nil)
        part = ["file", io, { filename: filename.to_s, content_type: content_type || DEFAULT_UPLOAD_TYPE }]
        request.set_form(fields.map { |key, value| [key.to_s, value.to_s] } + [part], "multipart/form-data")
        interpret(perform_upload(uri, request))
      end

      # GET a download link and yield its bytes as they arrive.
      #
      # This is the one call here that sends NO bearer token, and deliberately.
      # A download link is a capability: the UUID in it is the whole credential,
      # and the route serving it never looks at an Authorization header. Sending
      # the API key would put it on a request that has no use for it, at whatever
      # host the link happens to name.
      #
      # +link+ is the "url" an upload or a rotation answered with. It may be a
      # bare path when the deployment has no public base URL configured, which is
      # resolved against this client's own origin, since the two are served by the
      # same process.
      #
      # The body is never held whole: chunks are yielded as they are read, so a
      # file larger than this process's memory downloads fine.
      #
      # @param link [String] an absolute URL or a path beginning with "/"
      # @yieldparam chunk [String] binary
      # @return [nil]
      def download(link, &block)
        # Resolved OUTSIDE the rescue below, so a malformed link is reported as
        # the ArgumentError it is instead of being caught by the catch-all and
        # dressed up as the host being unreachable.
        uri = download_uri(link)
        perform_download(uri, &block)
      end

      # The escape hatch. A caller can reach a route this gem does not have a
      # method for yet, which will keep happening while the API is still
      # growing write endpoints, without dropping to raw Net::HTTP and losing
      # the safe decode and the error mapping along with it.
      #
      # @param verb [Symbol] :get, :patch, :post, :put or :delete, the same
      #   five {VERBS} knows
      # @param path [String] beginning with "/", relative to the mount
      # @param query [Hash, nil]
      # @param body [Hash, nil] form-encoded when flat, YAML when nested
      # @param raw [Boolean] true returns the response body as a String with
      #   no YAML decoding, for the one route that answers text/plain
      # @return [Hash, String, nil] nil for a 204
      def request(verb, path, query: nil, body: nil, raw: false)
        uri = url_for(path, query)
        response = perform(uri, build_request(verb, uri, body))
        interpret(response, raw: raw)
      end

      # Hold a server-sent event connection open and yield each frame's decoded
      # mapping.
      #
      # Written by hand for the same reason {#decode} is. The frames carry YAML
      # rather than the JSON every SSE example assumes, which works because SSE
      # joins a frame's consecutive "data:" lines with a newline before the
      # client sees them, so a multi-line YAML document rides one line per
      # frame line and reassembles exactly. Reassembling it here is a few
      # lines; getting a library to do it would mean one that already knows how
      # to not parse the payload as JSON.
      #
      # Comment frames are the heartbeats that keep an idle connection from
      # being reaped by a proxy. They are dropped rather than yielded, so a
      # caller never has to tell a real frame from a keep-alive.
      #
      # @param path [String]
      # @param query [Hash, nil]
      # @yieldparam frame [Hash]
      # @return [void]
      def stream(path, query: nil)
        uri = url_for(path, query)
        request = build_request(:get, uri, nil)
        request["Accept"] = "text/event-stream"

        stream_connection(uri) do |http|
          http.request(request) do |response|
            raise streamed_error(response) unless response.is_a?(Net::HTTPSuccess)

            buffer = +"".b
            response.read_body do |chunk|
              buffer << chunk
              yield_frames(buffer) { |frame| yield frame }
            end
          end
        end
      rescue StopIteration
        # The documented way for a caller's block to close the stream. Ending
        # the call normally is the whole point, so it stops here rather than
        # reaching the caller as an exception they would have to rescue around
        # their own break condition.
        nil
      end

      private

      # Peel complete frames off the front of +buffer+, leaving any partial one
      # behind. A chunk boundary lands mid-frame often enough that treating
      # each chunk as a frame would silently drop messages under load, which is
      # exactly the failure a live feed must not have.
      def yield_frames(buffer)
        while (index = buffer.index("\n\n"))
          raise MalformedResponse, "stream frame exceeds configured bound" if index + 2 > @max_frame_bytes

          frame = buffer.slice!(0, index + 2)
          document = decode_frame(frame)
          yield document unless document.nil?
        end
        raise MalformedResponse, "stream frame exceeds configured bound" if buffer.bytesize > @max_frame_bytes
      end

      # One frame's "data:" lines, rejoined and decoded. Returns nil for a
      # heartbeat or anything else carrying no data lines.
      def decode_frame(frame)
        payload = frame.lines.filter_map do |line|
          line.delete_prefix("data:").sub(/\A /, "").chomp if line.start_with?("data:")
        end
        return nil if payload.empty?

        decode(payload.join("\n"))
      end

      # The error path on a streamed response. The body has not been read off
      # the socket yet, so it is read here before the exception is built, which
      # is what puts the API's own "error" sentence into the message instead of
      # a bare status line.
      def streamed_error(response)
        read_bounded_body(response)
        error_for(response)
      rescue MalformedResponse
        raise
      rescue StandardError
        ApiError.new("the API answered #{response.code}", status: response.code.to_i)
      end

      # Net::HTTP.start with the read timeout lifted, since a stream is
      # supposed to sit idle between messages and the ordinary read timeout
      # would tear it down every time a room went quiet. The heartbeat is what
      # proves the connection is still alive instead.
      def stream_connection(uri)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: @open_timeout, read_timeout: nil) do |http|
          yield http
        end
      # StopIteration is listed alongside this gem's own errors because it is
      # how a caller's block asks the stream to close, and it descends from
      # StandardError, so without naming it here the ordinary connection
      # failure rescue below would swallow a clean shutdown and report it as
      # the API being unreachable.
      rescue Error, StopIteration
        raise
      rescue StandardError => e
        raise ConnectionError, "could not reach #{uri.host}: #{e.class}: #{e.message}"
      end

      # The read timeout is lifted for the same reason the upload lifts its
      # write timeout: a large file's transfer legitimately outlasts a timeout
      # sized for a request that answers with one small document.
      def perform_download(uri, &block)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: @open_timeout, read_timeout: nil) do |connection|
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = @user_agent
          connection.request(request) do |response|
            # Checked before a single chunk is yielded, so a caller writing to a
            # file never gets an error page written into it.
            unless response.is_a?(Net::HTTPSuccess)
              read_bounded_body(response)
              raise error_for(response)
            end

            response.read_body(&block)
          end
        end
        nil
      # Named first, so a status this mapped above is not then reported as the
      # host being unreachable.
      rescue Error
        raise
      rescue StandardError => e
        raise ConnectionError, "could not reach #{uri.host}: #{e.class}: #{e.message}"
      end

      # Where a download link points.
      #
      # A deployment with no public base URL configured answers with a bare path
      # rather than a full URL, which is resolved here against this client's own
      # origin: the download route and the API are served by one process, so that
      # is the right guess and the only one available.
      #
      # The mount path is deliberately NOT prepended. A download link is not an
      # API route, it sits at the web surface's own root.
      def download_uri(link)
        given = link.to_s.strip
        raise ArgumentError, "no download link given" if given.empty?

        uri = URI.parse(given)
        return uri if uri.is_a?(URI::HTTP)
        raise ArgumentError, "a download link must be an http URL or a path, got #{given.inspect}" unless given.start_with?("/")

        resolved = @root.dup
        resolved.path = uri.path
        resolved.query = uri.query
        resolved
      end

      def url_for(path, query)
        uri = @root.dup
        uri.path = "#{@mount}#{path}"
        uri.query = URI.encode_www_form(query) if query && !query.empty?
        uri
      end

      def build_request(verb, uri, body)
        klass = VERBS.fetch(verb) { raise ArgumentError, "unsupported HTTP verb #{verb.inspect}" }
        request = klass.new(uri)
        request["Accept"] = "application/yaml"
        request["Authorization"] = "Bearer #{@token}"
        request["User-Agent"] = @user_agent
        if body
          content_type, encoded = encode_body(body)
          request["Content-Type"] = content_type
          request.body = encoded
        end
        request
      end

      # A write body goes out form-encoded when it is flat and as YAML when it
      # is nested. The API accepts either (see App#write_body_params), and a
      # flat form body is the one that survives being retyped as a curl line
      # in a bug report. Nesting is where form encoding stops being obvious:
      # reaching a nested mapping means Rack's config[key]=value bracket
      # convention, a second encoding rule with its own edge cases, so the
      # feature PATCH's `config` mapping takes the YAML path instead.
      def encode_body(body)
        flat = body.values.none? { |value| value.is_a?(Hash) || value.is_a?(Array) }
        return ["application/x-www-form-urlencoded", URI.encode_www_form(stringify(body))] if flat

        ["application/yaml", YAMLCamel.dump(stringify(body))]
      end

      # Symbols become strings, keys and values alike, before anything is
      # written. The emitter would write a symbol as a plain scalar on its own,
      # so this is what makes the wire shape the client's own decision rather
      # than a detail of whichever writer is underneath it. A caller can pass a
      # symbol without having to know any of that.
      def stringify(value)
        case value
        when Hash then value.to_h { |key, val| [key.to_s, stringify(val)] }
        when Array then value.map { |item| stringify(item) }
        when Symbol then value.to_s
        else value
        end
      end

      # Net::HTTP.start with the read and write timeouts lifted, for an upload.
      # How long one takes is a function of the file and the link, and the far
      # end seals the whole thing before answering, so any figure that suits an
      # ordinary request would tear down a perfectly healthy transfer. The
      # connect timeout stays, since that is the one that detects a host which
      # is really not there.
      def perform_upload(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: @open_timeout, read_timeout: nil, write_timeout: nil) do |http|
          bounded_request(http, request)
        end
      rescue Error
        raise
      rescue StandardError => e
        raise ConnectionError, "could not reach #{uri.host}: #{e.class}: #{e.message}"
      end

      def perform(uri, request)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          bounded_request(http, request)
        end
      rescue Error
        raise
      rescue StandardError => e
        # Every socket-level failure is one situation from where the caller
        # sits: the API could not be reached, and nothing was learned about
        # whether the request took effect. The original is kept as the cause.
        raise ConnectionError, "could not reach #{uri.host}: #{e.class}: #{e.message}"
      end

      def bounded_request(http, request)
        http.request(request) do |response|
          read_bounded_body(response)
          response
        end
      end

      # The parser's input bound applies after receipt; enforce the transport
      # budget before appending each incoming chunk as well, for all statuses.
      def read_bounded_body(response)
        declared = response["Content-Length"]
        if declared&.match?(/\A\d+\z/) && declared.to_i > @max_response_bytes
          raise MalformedResponse, "response body exceeds configured bound"
        end
        body = +"".b
        response.read_body do |chunk|
          if chunk.bytesize > @max_response_bytes - body.bytesize
            raise MalformedResponse, "response body exceeds configured bound"
          end
          body << chunk
        end
        response.body = body
      end

      def interpret(response, raw: false)
        case response
        # Checked before Net::HTTPSuccess, which it descends from. A dozen
        # routes answer 204, mostly a revoke or a delete, and none has a body.
        when Net::HTTPNoContent then nil
        when Net::HTTPSuccess then raw ? response.body.to_s : decode(response.body)
        else raise error_for(response)
        end
      end

      # The reason this gem is written by hand rather than generated.
      #
      # This is the only way a response body is ever turned into Ruby here. A
      # YAML document can name a class to instantiate, and a loader that honours
      # that hands whoever can answer as the API a way to run code inside the
      # caller's process. The reader builds core schema types and nothing else,
      # so there is no list of permitted classes to get wrong and no document
      # that can reach a constructor. Nothing in this API's payloads needs a
      # Ruby type anyway: the server stringifies its own timestamps before
      # writing them, so every field arrives as a string, a number, a boolean, a
      # list or a mapping. Alias expansion is bounded by YAMLCamel::Limits, so a
      # small document from an untrusted source cannot expand into gigabytes.
      def decode(body)
        text = body.to_s
        return {} if text.strip.empty?

        parsed =
          begin
            YAMLCamel.load(text)
          rescue YAMLCamel::Error => e
            raise MalformedResponse, "the API sent a body this client will not load (#{e.class}: #{e.message})"
          end
        return {} if parsed.nil?
        raise MalformedResponse, "expected a YAML mapping from the API, got #{parsed.class}" unless parsed.is_a?(Hash)

        parsed
      end

      def error_for(response)
        status = response.code.to_i
        klass = STATUS_ERRORS.fetch(status, ApiError)
        message = error_message(response, status)
        body = response.body.to_s
        return klass.new(message, status: status, body: body) unless klass == RateLimited

        RateLimited.new(message, status: status, body: body, retry_after: retry_after(response))
      end

      # An error body from the API is a mapping with one `error` key. Anything
      # else arriving here came from in front of the app, most likely a
      # proxy's own HTML error page, so the status line is used instead: a
      # decode failure while building an exception would bury the status the
      # caller actually needs to see.
      def error_message(response, status)
        parsed = YAMLCamel.load(response.body.to_s)
        message = parsed.is_a?(Hash) ? parsed["error"].to_s : ""
        message.empty? ? "the API answered #{status} #{response.message}".strip : message
      rescue YAMLCamel::Error
        "the API answered #{status}"
      end

      def retry_after(response)
        value = response["Retry-After"].to_s
        value.match?(/\A\d+\z/) ? value.to_i : nil
      end
    end
  end
end
