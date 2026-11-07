# frozen_string_literal: true

require "json"

# Keep the supported surface derived from the pinned machine-readable contract,
# which accompanies source exports independently of private coverage notes.
OPENAPI_ROUTES = begin
  contract = JSON.parse(File.read(File.expand_path("release_api_contract.json", __dir__)))
  unsupported = contract.fetch("unsupported")
  contract.fetch("routes").reject { |route| unsupported.include?(route) }.map(&:freeze).freeze
end
