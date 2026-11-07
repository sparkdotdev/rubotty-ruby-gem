# Rubotty Client for Ruby

This gem calls Rubotty's HTTP API from Ruby. It provides methods and model objects for messaging, bridge integrations and a broad subset of administration routes. It connects to an existing service rather than running a bot itself.

Copyright 2026, Spark Software Development, LLC.

## Features

The client turns YAML responses into resource models, so code can read `room.label` instead of remembering a response hash's keys. List methods unwrap the documented resource envelope, while free-form configuration fields remain hashes.

Messaging methods cover rooms, channels, messages, edits and reactions, with a block-based room stream for live events. Bridge methods let another application send messages, edits and reactions as a remote endpoint.

The supported administration methods cover access grants, feature configuration and other control-plane resources. This client supports 139 of the 161 operations in the pinned API contract; the remaining 22 require direct calls or a future update.

Requests use Ruby's HTTP library and YAMLCamel for YAML. Status failures are mapped to specific errors, and the transport is exposed for a caller that needs a route without a convenience method. The API and gem are still pre-release, so pin a reviewed version and check its supported surface before upgrading.

## Configuration

Pass these keywords to `Rubotty::Client.new`. Load the API key from private application configuration.

| Keyword | Purpose |
| --- | --- |
| `token:` | Required developer or administrator API key. |
| `base_url:` | Required API root, including any mount path. |
| `open_timeout:` | Connect timeout in seconds; defaults to `5`. |
| `read_timeout:` | Read timeout in seconds; defaults to `15`. |
| `user_agent:` | Request identification; defaults to the gem name and version. |
| `max_response_bytes:` | Maximum buffered response size; defaults to 16 MiB. |
| `max_frame_bytes:` | Maximum pending event-frame size; defaults to 16 MiB. |

Pass explicit timeouts and handle API errors at your application boundary. The library does not load an environment file itself.

## Build & Deploy

Use Ruby 4.0 or newer. Run `bundle install` and `bundle exec rake` from the checkout, then `gem build rubotty-client.gemspec` to build the package. Require `rubotty/client` in the consuming application. The runtime needs `yamlcamel-ruby`; source-based Bundler installs must also declare that dependency until a compatible gem is available. Install or pin the reviewed client and YAML dependency together. Building a gem does not publish it to a package server.

## License

PolyForm Strict. Source-available, but not open-source. Free for non-commercial use. See [License](LICENSE.MD) for more information.

## Forking and Contributions

PolyForm Strict does not grant general permission to modify or redistribute this software. Our [Contribution Policy](CONTRIBUTING.md) grants limited permissions for contribution forks, review and controlled testing. Rights independently available under applicable law or the hosting platform's terms remain separate.

Contributions are welcome. You retain ownership, but Spark may use and commercially relicense submitted contributions, including under proprietary terms, even if a submission is declined or withdrawn. Read and accept the contribution agreement before submitting a change.
