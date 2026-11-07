# frozen_string_literal: true

require "spec_helper"

# Holds lib/rubotty/client.rb's route surface up against OPENAPI_ROUTES, the
# supported subset of the pinned machine-readable release_api_contract.json.
# The gap #4 named: nothing else in this repository fails a build the day the
# server grows a route this gem never gets a method for, or the day a gem
# method's path stops existing on the server. Says nothing about request or
# response bodies, only which routes exist; OPERATIONS in operations_spec.rb
# already drives every body end to end, and needs a live server for neither.
require 'json'

RSpec.describe "the gem's route surface against the API spec" do
  CLIENT_SOURCE = File.read(File.expand_path("../../../lib/rubotty/client.rb", __dir__))

  # Every "verb path" pair client.rb actually sends a request to, read
  # straight off its source rather than off a second hand-maintained list, so
  # this cannot itself drift from what the gem does. upload and stream count
  # as post and get: the wire verb they ride, {Transport#upload} and
  # {Transport#stream} name what shape the request takes rather than which
  # HTTP method it uses.
  def gem_routes
    routes = []
    CLIENT_SOURCE.scan(/@transport\.(get|post|put|patch|delete|upload|stream)\(\s*"(\/[^"]*)"/) do |verb, path|
      wire_verb = { "upload" => "post", "stream" => "get" }.fetch(verb, verb)
      routes << [wire_verb.upcase, normalize_gem_path(path)]
    end
    CLIENT_SOURCE.scan(/\blist(?:_of)?\(\s*(?:Models::\w+,\s*)?"(\/[^"]*)"/) do |path,|
      routes << ["GET", normalize_gem_path(path)]
    end
    routes.uniq
  end

  # A #{esc(slug)} interpolation normalizes to {X}, the same placeholder
  # {#normalize_spec_path} reduces a spec path's {slug} to, so a route
  # compares as the same shape on both sides without either naming its
  # parameters the same way.
  def normalize_gem_path(path) = path.gsub(/#\{esc\(\w+\)\}/, "{X}")

  def normalize_spec_path(path) = path.gsub(/\{[^}]+\}/, "{X}")

  def spec_routes
    OPENAPI_ROUTES.map { |verb, path| [verb, normalize_spec_path(path)] }.uniq
  end

  it "has a call site for every route in the supported subset" do
    missing = spec_routes - gem_routes
    expect(missing).to be_empty, -> { "the API documents a route with no call site in client.rb: #{missing.inspect}" }
  end

  it "has no call site left for a route the API spec no longer documents" do
    extra = gem_routes - spec_routes
    expect(extra).to be_empty, -> { "client.rb calls a route the API spec no longer documents: #{extra.inspect}" }
  end

  it "accounts explicitly for every operation in the pinned release contract" do
    contract = JSON.parse(File.read(File.expand_path("../../support/release_api_contract.json", __dir__)))
    routes = contract.fetch("routes").map { |verb, path| [verb, normalize_spec_path(path)] }
    unsupported = contract.fetch("unsupported").map { |verb, path| [verb, normalize_spec_path(path)] }
    expect(routes.uniq).to eq(routes)
    expect(unsupported.uniq).to eq(unsupported)
    expect(unsupported - routes).to be_empty
    expect(routes - gem_routes).to match_array(unsupported)
    expect(gem_routes - routes).to be_empty
    expect(routes.size).to eq(161)
    expect(unsupported.size).to eq(22)
  end

  it "keeps the README supported count consistent with the machine contract" do
    readme = File.read(File.expand_path("../../../README.md", __dir__))
    expect(readme.scan(/supports (\d+) of the (\d+) operations/)).to eq([["139", "161"]])
  end

  # A guard on the guard: a mistake that emptied OPENAPI_ROUTES, or a
  # normalization bug that collapsed every route to the same placeholder,
  # would otherwise pass both examples above by proving nothing.
  it "vendors a route list the size of what the spec actually documents" do
    expect(OPENAPI_ROUTES.size).to eq(139)
    expect(gem_routes.size).to eq(139)
  end
end
