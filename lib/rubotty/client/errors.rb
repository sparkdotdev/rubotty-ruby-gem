# frozen_string_literal: true

module Rubotty
  class Client
    # Everything this client raises descends from here, so a caller that only
    # wants "the API call failed" can rescue one class and a caller that wants
    # to branch on why can rescue a specific one.
    class Error < StandardError; end

    # The request never got an answer: DNS, TLS, a refused connection, a
    # timeout. Kept apart from {ApiError} because there is no status and no
    # body to inspect, and because retrying is often the right response to
    # this and rarely the right response to a 4xx.
    class ConnectionError < Error; end

    # The API answered, but the body was not something this client is willing
    # to turn into Ruby: unparseable YAML, a document carrying a tag or an
    # alias the safe loader refuses, a body that is not a mapping, or a list
    # response missing its envelope key. Raised rather than papered over,
    # since a client that guesses at a body it does not understand is how a
    # caller ends up acting on data that was never there.
    class MalformedResponse < Error; end

    # A response with a status the API defines a meaning for. +status+ is the
    # integer code and +body+ is the raw response body, kept so an unexpected
    # failure can be logged in full without a second request.
    class ApiError < Error
      attr_reader :status, :body

      def initialize(message, status:, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    # 400. The request body was not a YAML mapping, or a feature write's
    # `config` was not a mapping. Reachable from this client only if a caller
    # passes something odd to a write method or drives {Client#transport}
    # directly, since the encoding here is otherwise fixed.
    class BadRequest < ApiError; end

    # 401. Missing, malformed, unknown or revoked bearer token. Every route
    # but /healthz can answer this, and a revoked key produces it on the next
    # call with no warning, since the key is resolved fresh on every request
    # rather than cached.
    class Unauthorized < ApiError; end

    # 403. A route-class scope failure: a developer key reached for an
    # /admin/... route. It says nothing about whether any particular resource
    # exists, only that this class of route is outside the key's world. A
    # developer key gets this on every /admin/... path regardless of which
    # community the path names.
    class Forbidden < ApiError; end

    # 404. Two different situations arrive here wearing the same body: the
    # thing does not exist, and the thing belongs to a community this key
    # cannot see. The API makes them indistinguishable on purpose, so a
    # developer key can never probe for what exists in another community by
    # watching which ids answer differently. There is nothing in the response
    # to tell them apart, and there is not supposed to be.
    class NotFound < ApiError; end

    # 422. A control-plane service refused the write: an unknown feature name,
    # a room selector that matched nothing, and similar. The message comes
    # straight from the `error` key of the response body, which is the same
    # sentence the dashboard and the CLI would have shown for that refusal.
    class ValidationFailed < ApiError; end

    # 429. The key's per-window budget is exhausted. The limit is applied
    # during authentication, before any route runs, so this can answer any
    # authenticated call and not only the ones documented with a 429.
    class RateLimited < ApiError
      # Seconds to wait, from the Retry-After header, or nil when the header
      # was absent or not a plain integer. The API sends seconds; the RFC also
      # allows an HTTP date there, which this deliberately does not try to
      # parse into a number, since a caller sleeping for a misread date would
      # be worse than a caller told it does not know.
      attr_reader :retry_after

      def initialize(message, status:, body: nil, retry_after: nil)
        super(message, status: status, body: body)
        @retry_after = retry_after
      end
    end
  end
end
