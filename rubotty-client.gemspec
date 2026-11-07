# frozen_string_literal: true

require_relative "lib/rubotty/client/version"

Gem::Specification.new do |spec|
  spec.name = "rubotty-client"
  spec.version = Rubotty::Client::VERSION
  spec.authors = ["mszaro"]
  spec.email = ["matt@szaro.org"]

  spec.summary = "Ruby client for the rubotty REST admin API"
  spec.description = <<~TEXT
    A hand-written Ruby client for the rubotty REST admin API, covering a documented subset of 139
    read and write operations across communities, rooms, channels, bridged
    remote systems, people, operators, viewers, auth tokens, features, word
    filters, FAQ entries, join links, platform wiring, guest invites, events,
    onboarding, room participation, live messaging including the server-sent
    event room stream, and the administrator-only routes for scripts, the
    outbound endpoints they call, webhooks, backfill proposals, analytics and
    debug.

    PRE-ALPHA. Version 0.1.6 tracks an API that is still unstable and still
    growing endpoints. Method names and return shapes will change in breaking
    ways before 1.0, in patch releases, with no deprecation cycle. Pin an
    exact version.

    The API answers YAML on every route, and responses are decoded with
    yamlcamel-ruby, which builds core schema types and nothing else, then
    built into a typed model object under Rubotty::Client::Models:
    client.room(slug, key).label rather than client.room(slug, key)["label"].
    A field that is genuinely free-form in the API stays a plain Hash. Pure
    Ruby throughout, so installing it never runs a compiler.
  TEXT

  spec.required_ruby_version = ">= 4.0"

  spec.license = "LicenseRef-PolyForm-Strict-1.0.0"

  spec.homepage = "https://github.com/sparkdotdev/rubotty-ruby-gem"
  spec.metadata["rubygems_mfa_required"] = "true"
  # Publishing is an explicit release step after the dependency is available.
  # Keep this guard until package ownership and the release version are verified.
  spec.metadata["allowed_push_host"] = "https://none.invalid"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE.MD CONTRIBUTING.md rubotty-client.gemspec]
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "yamlcamel-ruby", "~> 0.1"
end
