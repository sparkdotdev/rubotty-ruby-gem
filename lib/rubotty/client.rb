# frozen_string_literal: true

require_relative "client/version"
require_relative "client/errors"
require_relative "client/transport"
require_relative "client/models"

module Rubotty
  # A client for the rubotty REST admin API.
  #
  # ## What comes back
  #
  # A typed model object from {Models}, never a bare Hash or Array with
  # string keys to remember and mistype. `client.room("sample", "general").label`
  # reads and refactors like Ruby; `client.room("sample", "general")["label"]`
  # only looks like it does until the key is wrong and nothing catches it.
  #
  # A list route returns `Array<Models::SomeModel>`, unwrapped from its
  # envelope. A single resource returns its model. A delete returns true,
  # except the handful that remove one entry from a small hand-managed list,
  # the word filter and the FAQ among them, which answer with the survivors
  # instead so a caller never has to read the list back separately to see
  # what is left; the word filter's survivors stay plain strings, since that
  # is genuinely all a word filter entry is, and the FAQ's come back as
  # `Array<Models::FaqEntry>`.
  #
  # Nesting follows the API: {Models::Room} carries its channel keys as
  # plain strings because that is all the API sends for them, {Models::StreamFrame}
  # carries `Array<Models::StreamMessage>` because the API nests full message
  # rows there. A field that is genuinely open-ended in the API, a feature's
  # `config`, an account's `settings`, stays a plain Hash rather than being
  # forced into a shape it does not have: see {Models::Base} for how a model
  # is actually built from the Hash {Transport} decodes.
  #
  # ## Scope
  #
  # A developer key is confined to one community; an administrator key sees all
  # of them. The method surface is the same either way, and the key decides what
  # answers and what refuses. Methods prefixed `admin_` need an administrator
  # key.
  class Client
    USER_AGENT = "rubotty-client/#{VERSION}"

    # The transport, exposed so a caller can reach a route that has no method
    # here yet. See {Transport#request}.
    attr_reader :transport

    # @param token [String] a developer or administrator API key, issued from
    #   the dashboard's /api-keys page. Required at construction, so a missing
    #   key fails here rather than on the first call.
    # @param base_url [String] the API root, mount path included
    # @param open_timeout [Numeric] seconds
    # @param read_timeout [Numeric] seconds. Larger than the connect timeout,
    #   since the stats and debug-log routes are slower than the rest.
    # @param user_agent [String]
    def initialize(token:, base_url: nil,
                   open_timeout: Transport::DEFAULT_OPEN_TIMEOUT,
                   read_timeout: Transport::DEFAULT_READ_TIMEOUT,
                   user_agent: USER_AGENT,
                   max_response_bytes: Transport::DEFAULT_MAX_RESPONSE_BYTES,
                   max_frame_bytes: Transport::DEFAULT_MAX_FRAME_BYTES)
      key = token.to_s.strip
      raise ArgumentError, "an API token is required" if key.empty?

      @transport = Transport.new(base_url: base_url, token: key, open_timeout: open_timeout,
                                 read_timeout: read_timeout, user_agent: user_agent,
                                 max_response_bytes: max_response_bytes, max_frame_bytes: max_frame_bytes)
    end

    def base_url = @transport.base_url

    # ------------------------------------------------------------------
    # Health
    # ------------------------------------------------------------------

    # Liveness. The one route that needs no key, and the only one answering
    # plain text, so the body comes back as a raw String rather than a model.
    def ping = @transport.get("/healthz", raw: true)

    # ------------------------------------------------------------------
    # Communities
    # ------------------------------------------------------------------

    # A developer key reads its own community here and 404s on any other slug,
    # including a slug that really exists elsewhere.
    #
    # @return [Models::Community]
    def community(slug) = Models::Community.from_h(@transport.get("/communities/#{esc(slug)}"))

    # Administrator only. Ordered by slug.
    #
    # @return [Array<Models::Community>]
    def admin_communities = list_of(Models::Community, "/admin/communities", "communities")

    # ------------------------------------------------------------------
    # Rooms and channels
    # ------------------------------------------------------------------

    # Each room carries the endpoint_keys of every channel bridged into it, so
    # knowing what a room spans takes no second call.
    #
    # @return [Array<Models::Room>]
    def rooms(slug) = list_of(Models::Room, "/communities/#{esc(slug)}/rooms", "rooms")

    # @return [Models::Room]
    def room(slug, room_key)
      Models::Room.from_h(@transport.get("/communities/#{esc(slug)}/rooms/#{esc(room_key)}"))
    end

    # ------------------------------------------------------------------
    # Messaging
    # ------------------------------------------------------------------

    # Enqueue a message for delivery to every platform bridged into the room.
    #
    # Answers 201 with a status of "queued". Accepted, not delivered: the
    # message is screened by the community's moderation settings first, and one
    # they reject is dropped without any further notice here.
    #
    # An empty body, or one over 4000 characters, raises {ValidationFailed}.
    #
    # @return [Models::MessageQueued]
    def post_message(slug, room_key, body)
      Models::MessageQueued.from_h(
        @transport.post("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/messages", { "body" => body.to_s })
      )
    end

    # Edit a message posted to a room earlier.
    #
    # An empty body raises {ValidationFailed}.
    #
    # @return [Models::QueuedStatus]
    def edit_message(slug, room_key, message_id, body)
      Models::QueuedStatus.from_h(
        @transport.patch("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/messages/#{esc(message_id)}",
                         { "body" => body.to_s })
      )
    end

    # Delete a message posted to a room earlier.
    #
    # @return [Models::QueuedStatus]
    def delete_message(slug, room_key, message_id)
      Models::QueuedStatus.from_h(
        @transport.delete("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/messages/#{esc(message_id)}")
      )
    end

    # Add a reaction to a message posted to a room.
    #
    # @param reaction [Hash] at least one of "emoji" or "custom_id" is
    #   required, plus an optional "custom_name" shown where the native image
    #   cannot cross platforms. Raises {ValidationFailed} when neither is given.
    # @return [Models::QueuedStatus]
    def add_reaction(slug, room_key, message_id, reaction)
      Models::QueuedStatus.from_h(
        @transport.put("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/messages/#{esc(message_id)}/reactions",
                       { "reaction" => reaction })
      )
    end

    # @see #add_reaction
    # @return [Models::QueuedStatus]
    def remove_reaction(slug, room_key, message_id, reaction)
      Models::QueuedStatus.from_h(
        @transport.delete(
          "/communities/#{esc(slug)}/rooms/#{esc(room_key)}/messages/#{esc(message_id)}/reactions",
          { "reaction" => reaction }
        )
      )
    end

    # Watch a room live, yielding each frame as a {Models::StreamFrame} as it
    # arrives.
    #
    # Blocks for as long as the stream is open, which is indefinitely against a
    # real deployment. Raise StopIteration from the block to close it cleanly;
    # anything else raised propagates after the connection is torn down.
    #
    # New messages only. An edit, a delete or a reaction never reaches the
    # buffer this reads, so a subscriber sees what was said and not what
    # happened to it afterwards. There is no backlog either: with no +since+ a
    # subscriber starts at the room's current head, so opening a stream never
    # hands over a conversation they were not part of.
    #
    # Each frame carries `room_key`, `cursor` and `messages`, the last an
    # `Array<Models::StreamMessage>`. The first frame arrives immediately with
    # an empty `messages`, so a caller confirms the stream is live and pins
    # its cursor even on a silent room. Heartbeats are dropped here rather
    # than yielded as empty frames.
    #
    #   cursor = nil
    #   client.stream_room("sample", "general") do |frame|
    #     cursor = frame.cursor
    #     frame.messages.each { |m| puts "#{m.author}: #{m.body}" }
    #     raise StopIteration if done?
    #   end
    #
    # @param since [Integer, nil] resume after this cursor. The `cursor` of the
    #   last frame handled is what to pass on a reconnect.
    # @yieldparam frame [Models::StreamFrame]
    # @return [void]
    def stream_room(slug, room_key, since: nil, &block)
      raise ArgumentError, "stream_room needs a block to yield frames to" if block.nil?

      @transport.stream("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/stream",
                        query: compact(since: since)) do |frame|
        block.call(Models::StreamFrame.from_h(frame))
      end
    end

    # ------------------------------------------------------------------
    # Bridge: a remote system posting in as a first party platform
    # ------------------------------------------------------------------
    #
    # Reachable only with an API key scoped to one platform_account, never
    # with an ordinary developer or administrator key. A channel_id that
    # account has no mapping for, and another community's slug, both raise
    # {NotFound} the same as a route that does not exist.
    #
    # +author+, +reaction+ and +attachments+ below stay plain Hashes on the
    # way in rather than models of their own: they are write-only shapes this
    # gem never hands back, so there is nothing for a caller to read off one
    # and no fragility a model would save them from.

    # Enqueue a message from a bridged remote system, for delivery to every
    # OTHER platform bridged into the same room. Answers 201 with the new
    # message's id, which a later edit, delete or reaction on this same
    # channel addresses.
    #
    # @param body [String, nil] the message text. May be left empty only when
    #   +attachments+ carries at least one entry, or the whole call raises
    #   {ValidationFailed}.
    # @param author [Hash, nil] the real person on the remote system who sent
    #   it, so the room shows who actually said it rather than the
    #   integration's own name every time. Takes "id", "name" and
    #   "avatar_url".
    # @param reply_to [String, nil] the message_id of an earlier post in this
    #   same channel that this one replies to
    # @param attachments [Array<Hash>, nil] each needing a publicly fetchable
    #   "url", plus optional "filename", "mime_type", "kind" and "caption"
    # @return [Models::BridgeMessageQueued]
    def post_bridge_message(slug, channel_id, body: nil, author: nil, reply_to: nil, attachments: nil)
      Models::BridgeMessageQueued.from_h(
        @transport.post("/communities/#{esc(slug)}/bridge/channels/#{esc(channel_id)}/messages",
                        compact(body: body, author: author, reply_to: reply_to, attachments: attachments))
      )
    end

    # Edit a message a bridged remote system posted earlier.
    #
    # @param body [String] the message's new text. Empty raises {ValidationFailed}.
    # @param author [Hash, nil] @see #post_bridge_message
    # @return [Models::QueuedStatus]
    def edit_bridge_message(slug, channel_id, message_id, body:, author: nil)
      Models::QueuedStatus.from_h(
        @transport.patch("/communities/#{esc(slug)}/bridge/channels/#{esc(channel_id)}/messages/#{esc(message_id)}",
                         compact(body: body, author: author))
      )
    end

    # Delete a message a bridged remote system posted earlier.
    #
    # @param author [Hash, nil] @see #post_bridge_message
    # @return [Models::QueuedStatus]
    def delete_bridge_message(slug, channel_id, message_id, author: nil)
      Models::QueuedStatus.from_h(
        @transport.delete("/communities/#{esc(slug)}/bridge/channels/#{esc(channel_id)}/messages/#{esc(message_id)}",
                          author.nil? ? nil : { "author" => author })
      )
    end

    # Add a reaction to a message on a bridged remote system, on behalf of
    # the author named in the body rather than the integration itself:
    # several different remote people may each hold their own reaction on
    # the same message.
    #
    # @param reaction [Hash] at least one of "emoji" or "custom_id" is
    #   required, plus an optional "custom_name" shown where the native image
    #   cannot cross platforms. Raises {ValidationFailed} when neither is given.
    # @param author [Hash, nil] @see #post_bridge_message
    # @return [Models::QueuedStatus]
    def add_bridge_reaction(slug, channel_id, message_id, reaction:, author: nil)
      Models::QueuedStatus.from_h(
        @transport.put("/communities/#{esc(slug)}/bridge/channels/#{esc(channel_id)}/messages/#{esc(message_id)}/reactions",
                       compact(reaction: reaction, author: author))
      )
    end

    # @see #add_bridge_reaction
    # @return [Models::QueuedStatus]
    def remove_bridge_reaction(slug, channel_id, message_id, reaction:, author: nil)
      Models::QueuedStatus.from_h(
        @transport.delete(
          "/communities/#{esc(slug)}/bridge/channels/#{esc(channel_id)}/messages/#{esc(message_id)}/reactions",
          compact(reaction: reaction, author: author)
        )
      )
    end

    # @return [Array<Models::Channel>]
    def channels(slug) = list_of(Models::Channel, "/communities/#{esc(slug)}/channels", "channels")

    # @return [Models::Channel]
    def channel(slug, endpoint_key)
      Models::Channel.from_h(@transport.get("/communities/#{esc(slug)}/channels/#{esc(endpoint_key)}"))
    end

    # Channels rubotty has found that are not yet mapped into a room.
    # Read-only: approve and reject are not available over the API.
    #
    # @return [Array<Models::Channel>]
    def discovered_channels(slug)
      list_of(Models::Channel, "/communities/#{esc(slug)}/discovered-channels", "discovered_channels")
    end

    # What the server would map each discovered channel to, worked out by
    # comparing names. Writes nothing, so this is safe to call and throw away.
    # Every discovered channel comes back with an action of "bind", "create" or
    # "skip"; a skip carries the reason it was left alone rather than being
    # left out of the list.
    #
    # @return [Array<Models::MappingProposal>]
    def mapping_proposals(slug)
      list_of(Models::MappingProposal, "/communities/#{esc(slug)}/discovered-channels/mapping-proposals", "proposals")
    end

    # Apply the mappings named in +mappings+, which is normally the subset of
    # {#mapping_proposals} the caller agrees with rather than all of it. Each
    # entry wants an "endpoint_key" and a "room_key", plus an optional
    # "room_label" used only when the room is being created.
    #
    # Compare the returned `requested` against `applied` to see whether
    # anything was dropped: a channel that stopped being discovered-and-unmapped
    # between proposing and applying is skipped rather than acted on.
    #
    # @return [Models::MappingApplyResult]
    def apply_mapping_proposals(slug, mappings)
      Models::MappingApplyResult.from_h(
        @transport.post(
          "/communities/#{esc(slug)}/discovered-channels/mapping-proposals/apply",
          { "mappings" => Array(mappings) }
        )
      )
    end

    # The single-channel form of applying a mapping. {#apply_mapping_proposals}
    # takes a whole list and skips whatever went stale between reading and
    # submitting; this takes one channel and says plainly when it cannot be
    # mapped.
    #
    # Mapping enables no feature. The channel is linked into the room's
    # topology and stays as dormant as it was.
    #
    # @param room_key [String, nil] an existing room to join, or the key for
    #   a fresh one
    # @param partner [String, nil] another discovered, unmapped channel's
    #   endpoint key, to seed a new room alongside
    # @param solo [Boolean, nil] put this channel in a room of its own
    # @param label [String, nil] the display name for a room being created.
    #   Ignored when the room already exists.
    # @return [Models::ChannelMapping] the room, and every channel now in it.
    #   Naming none of room_key:, partner: or solo: raises {ValidationFailed}.
    def map_discovered_channel(slug, endpoint_key, room_key: nil, partner: nil, solo: nil, label: nil)
      Models::ChannelMapping.from_h(
        @transport.post(
          "/communities/#{esc(slug)}/discovered-channels/#{esc(endpoint_key)}/map",
          compact(room_key: room_key, partner: partner, solo: solo, label: label)
        )
      )
    end

    # Channels a non-operator named with the topic command, waiting on a
    # decision. Recorded as a suggestion rather than taken as identified,
    # since whoever named it may not run the community.
    #
    # @return [Array<Models::SuggestedChannel>]
    def suggested_channels(slug)
      list_of(Models::SuggestedChannel, "/communities/#{esc(slug)}/suggested-channels", "suggested_channels")
    end

    # Keep a suggested channel. It stops being a suggestion and nothing else
    # about it changes: the label it was named with stands, and it joins no
    # room by being approved. A suggestion already settled raises {NotFound}.
    #
    # @return [Models::SuggestedChannel]
    def approve_suggested_channel(slug, id)
      Models::SuggestedChannel.from_h(
        @transport.post("/communities/#{esc(slug)}/suggested-channels/#{esc(id)}/approve")
      )
    end

    # Drop a suggested channel outright, which is why there is nothing to
    # return. Only a suggestion still waiting on a decision is reachable
    # here, so an approved one cannot be removed by guessing its id.
    #
    # @return [true]
    def reject_suggested_channel(slug, id)
      @transport.post("/communities/#{esc(slug)}/suggested-channels/#{esc(id)}/reject")
      true
    end

    # ------------------------------------------------------------------
    # People and operators
    # ------------------------------------------------------------------

    # The passively observed identity directory. There is no create verb
    # anywhere for a person: a row appears by observing someone talk.
    #
    # @return [Array<Models::Person>]
    def people(slug) = list_of(Models::Person, "/communities/#{esc(slug)}/people", "people")

    # @return [Models::Person]
    def person(slug, id) = Models::Person.from_h(@transport.get("/communities/#{esc(slug)}/people/#{esc(id)}"))

    # Set the name this person is bridged as on one platform. The platform in
    # +adapter+ is where the name is SHOWN, never where the person was
    # observed. Returns the whole person, so what actually saved can be read
    # rather than assumed.
    #
    # First come wins within a community and platform: a name somebody else
    # already answers to there raises {ValidationFailed}, as does a name
    # between 2 and 64 characters that the community would never have
    # accepted.
    #
    # @return [Models::Person]
    def set_nickname(slug, id, adapter, nickname:)
      Models::Person.from_h(
        @transport.put("/communities/#{esc(slug)}/people/#{esc(id)}/nicknames/#{esc(adapter)}",
                       { "nickname" => nickname.to_s })
      )
    end

    # Drop the name this person is bridged as on one platform. They go back
    # to whatever label the bridge would otherwise build for them. Raises
    # {NotFound} when they hold no name on that platform.
    #
    # Unlike {#set_nickname} this is never refused on the community's own
    # policy: clearing a name that has become a problem is the lever an
    # operator keeps whatever that policy is.
    #
    # @return [true]
    def clear_nickname(slug, id, adapter)
      @transport.delete("/communities/#{esc(slug)}/people/#{esc(id)}/nicknames/#{esc(adapter)}")
      true
    end

    # Every granted operator, each either a {Models::Operator} or, for a
    # handle the deployment ships with as an owner, a {Models::BakedInOperator}.
    # The two share enough of a shape (`actions`, `scope`, `baked_in`,
    # `removable`) that a caller not sorting on `baked_in` can treat the list
    # uniformly.
    #
    # @return [Array<Models::Operator, Models::BakedInOperator>]
    def operators(slug)
      unwrap(@transport.get("/communities/#{esc(slug)}/operators"), "operators").map { |row| build_operator(row) }
    end

    # Make somebody an operator of this community. Administrator only, which
    # is the whole reason this write sits under /admin/ while {#operators}
    # stays on the ordinary community path: reading who runs a community a
    # key already reaches tells that key nothing new, and deciding who runs
    # it is a different thing entirely.
    #
    # Named by platform account rather than by person, since the person may
    # have no record yet; one is created for them, the same way approving
    # their operator request would. Idempotent: somebody already an operator
    # keeps the record and the scope they have.
    #
    # @param native_id [String] the platform's own id for the account, the
    #   reliable half of the name
    # @param username [String, nil] their handle on that platform
    # @param display [String, nil] their display name, used to name a freshly
    #   created person record
    # @return [Models::Operator]
    def admin_grant_operator(slug, adapter:, native_id:, username: nil, display: nil)
      Models::Operator.from_h(
        @transport.post("/admin/communities/#{esc(slug)}/operators",
                        compact(adapter: adapter, native_id: native_id, username: username, display: display))
      )
    end

    # Stop somebody operating this community. Raises {ValidationFailed} for
    # somebody the deployment also ships with as an owner: the record would
    # go while the shipped floor kept handing them the same access here and
    # everywhere else, so the call would read as a revocation and would not
    # be one.
    #
    # @return [true]
    def admin_revoke_operator(slug, id)
      @transport.delete("/admin/communities/#{esc(slug)}/operators/#{esc(id)}")
      true
    end

    # Every request whatever its state, pending and decided alike.
    #
    # @return [Array<Models::OperatorRequest>]
    def operator_requests(slug)
      list_of(Models::OperatorRequest, "/communities/#{esc(slug)}/operator-requests", "operator_requests")
    end

    # @return [Models::OperatorRequest]
    def operator_request(slug, id)
      Models::OperatorRequest.from_h(@transport.get("/communities/#{esc(slug)}/operator-requests/#{esc(id)}"))
    end

    # ------------------------------------------------------------------
    # Viewers and auth tokens, community scoped
    # ------------------------------------------------------------------
    #
    # A community viewer reads ONE community and changes nothing in it. On
    # the ordinary community path rather than under /admin/..., which is the
    # whole difference from {#admin_viewers}: a developer key confined to
    # this community may hand this out, because it reaches no further than
    # that key already reaches.

    # Two lists. `viewers` are the granted entries for this community, which
    # {#revoke_community_viewer} can remove; `baked_in` are the handles the
    # deployment ships with, which read every community and cannot be
    # revoked anywhere.
    #
    # @return [Models::CommunityViewerRoster]
    def community_viewers(slug)
      Models::CommunityViewerRoster.from_h(@transport.get("/communities/#{esc(slug)}/viewers"))
    end

    # Let a handle read this community. Named by the platform handle a
    # person owns, never by a display name, which anyone can set to
    # anything. Idempotent: granting a handle that already reads this
    # community answers the existing entry. A handle the deployment already
    # ships with raises {ValidationFailed}, since the resulting entry would
    # look revocable and would not be.
    #
    # native_id binds the grant to a stable account. When omitted, the API must
    # resolve the handle to one known identity or refuse it.
    # @return [Models::CommunityViewer]
    def grant_community_viewer(slug, adapter:, handle:, label: nil, native_id: nil)
      Models::CommunityViewer.from_h(
        @transport.post("/communities/#{esc(slug)}/viewers",
                        compact(adapter: adapter, handle: handle, label: label, native_id: native_id))
      )
    end

    # Stop a handle reading this community. Raises {ValidationFailed} when
    # the deployment also ships with that handle.
    #
    # @return [true]
    def revoke_community_viewer(slug, id)
      @transport.delete("/communities/#{esc(slug)}/viewers/#{esc(id)}")
      true
    end

    # Open requests to read this community, oldest first. Filed by DMing the
    # bot `/role viewer`. An operator of this community decides one, unlike
    # {#admin_viewer_requests}, which spans every community and so only an
    # administrator may decide.
    #
    # @return [Array<Models::CommunityViewerRequest>]
    def community_viewer_requests(slug)
      list_of(Models::CommunityViewerRequest, "/communities/#{esc(slug)}/viewer-requests", "viewer_requests")
    end

    # Grant a pending request to read this community. The request is marked
    # approved and the requester's handle is granted in the same call.
    #
    # @return [Models::CommunityViewerRequestDecision] the decided request,
    #   and the viewer it produced
    def approve_community_viewer_request(slug, id)
      Models::CommunityViewerRequestDecision.from_h(
        @transport.post("/communities/#{esc(slug)}/viewer-requests/#{esc(id)}/approve")
      )
    end

    # Refuse a pending request to read this community. Grants nothing. A
    # denied request does not block a later one, so somebody refused today
    # can ask again.
    #
    # @return [Models::CommunityViewerRequest]
    def deny_community_viewer_request(slug, id)
      body = @transport.post("/communities/#{esc(slug)}/viewer-requests/#{esc(id)}/deny")
      Models::CommunityViewerRequest.from_h(unwrap(body, "request"))
    end

    # The tokens minted for this one community, newest first. The token
    # strings are not here and cannot be: only their digests are kept.
    #
    # @return [Array<Models::AuthToken>]
    def community_auth_tokens(slug)
      list_of(Models::AuthToken, "/communities/#{esc(slug)}/auth-tokens", "auth_tokens")
    end

    # Mint a token that hands over a role in this community when redeemed
    # with the bot's `/auth` command. The answer carries the token string,
    # and it is the only time it is ever readable.
    #
    # @param operator [Boolean, nil] whether redeeming it makes the holder an
    #   operator here. Needs an administrator key; a developer key raises
    #   {ValidationFailed}.
    # @param viewer [Boolean, nil] whether redeeming it lets the holder read
    #   this community and change nothing in it. A developer key may hand
    #   this over, which changes nothing here.
    # @param ttl_seconds [Integer, nil] how long it stays redeemable.
    #   Defaults to a day, and a fortnight is the most it may be.
    # @return [Models::IssuedAuthToken] carries `token`, shown here and nowhere else
    def mint_community_auth_token(slug, operator: nil, viewer: nil, ttl_seconds: nil, label: nil)
      Models::IssuedAuthToken.from_h(
        @transport.post("/communities/#{esc(slug)}/auth-tokens",
                        compact(operator: operator, viewer: viewer, ttl_seconds: ttl_seconds, label: label))
      )
    end

    # Take a token back before it is used. Raises {ValidationFailed} once the
    # token has been redeemed: the role it carried is already granted by
    # then, so revoking it would say something untrue.
    #
    # @return [true]
    def revoke_community_auth_token(slug, public_id)
      @transport.delete("/communities/#{esc(slug)}/auth-tokens/#{esc(public_id)}")
      true
    end

    # ------------------------------------------------------------------
    # Features
    # ------------------------------------------------------------------

    # What `config` accepts for each feature: the same schema the dashboard
    # reads to build its per-feature config form. Deployment-wide rather than
    # community-scoped, since the shape is identical for every community, and
    # the only authority on config keys: a config's real shape belongs to
    # whatever release the deployment is running rather than to this gem.
    #
    # @return [Array<Models::FeatureSchema>]
    def feature_schemas = list_of(Models::FeatureSchema, "/features/schema", "features")

    # The community-wide defaults, meaning every feature row with no room
    # attached to it.
    #
    # @return [Array<Models::Feature>]
    def community_features(slug) = list_of(Models::Feature, "/communities/#{esc(slug)}/features", "features")

    # @return [Models::Feature]
    def community_feature(slug, feature)
      Models::Feature.from_h(@transport.get("/communities/#{esc(slug)}/features/#{esc(feature)}"))
    end

    # Sets the community-wide default's enabled state, its config, or both,
    # and returns the row as it stands afterwards.
    #
    # Each config key is coerced on the way
    # in, the same path a `rubotty feature set` call takes, so "true", "5" and
    # "a,b,c" land as a boolean, a number and a list. Passing real Ruby types
    # works too, since a nested config goes out as YAML.
    #
    # @param enabled [Boolean, nil] nil leaves the current state alone
    # @param config [Hash, nil] merged key by key; nil leaves config alone
    # @return [Models::Feature]
    def set_community_feature(slug, feature, enabled: nil, config: nil)
      Models::Feature.from_h(
        @transport.patch("/communities/#{esc(slug)}/features/#{esc(feature)}", feature_body(enabled: enabled, config: config))
      )
    end

    # Only what has been set on this room explicitly. A feature the room
    # inherits from the community default has no row and is simply absent, so
    # this answers "what is configured here" and not "what is in effect here".
    #
    # @return [Array<Models::Feature>]
    def room_features(slug, room_key)
      list_of(Models::Feature, "/communities/#{esc(slug)}/rooms/#{esc(room_key)}/features", "features")
    end

    # @return [Models::RoomFeature] what the feature resolves to here, and
    #   whether that came from the room's own override or the community default
    def room_feature(slug, room_key, feature)
      Models::RoomFeature.from_h(
        @transport.get("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/features/#{esc(feature)}")
      )
    end

    # @see #set_community_feature
    # @return [Models::Feature]
    def set_room_feature(slug, room_key, feature, enabled: nil, config: nil)
      Models::Feature.from_h(
        @transport.patch("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/features/#{esc(feature)}",
                         feature_body(enabled: enabled, config: config))
      )
    end

    # Drops the room's own row so the feature inherits the community default
    # again. A room with no override raises {NotFound}.
    #
    # @return [true] the override was removed
    def reset_room_feature(slug, room_key, feature)
      @transport.delete("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/features/#{esc(feature)}")
      true
    end

    # ------------------------------------------------------------------
    # Word filter, FAQ, join links
    # ------------------------------------------------------------------

    # The filtered words, as an array of strings. Stays plain strings rather
    # than a model: a word filter entry has no shape beyond the text itself.
    #
    # @return [Array<String>]
    def word_filter_entries(slug) = list("/communities/#{esc(slug)}/word-filter/entries", "entries")

    # Replace the community-wide list outright. The one write the underlying
    # list supports: adding a single word still means sending the complete
    # list back.
    #
    # @return [Array<String>] the list as it stands afterwards
    def replace_word_filter_entries(slug, entries)
      body = @transport.put("/communities/#{esc(slug)}/word-filter/entries", { "entries" => Array(entries) })
      unwrap(body, "entries")
    end

    # Remove one word or phrase from the community-wide list, addressed by
    # its own value rather than by position: there is no id for these
    # entries. Raises {ValidationFailed} when the value is not in the
    # current list.
    #
    # @return [Array<String>] the list as it stands afterwards
    def remove_word_filter_entry(slug, value)
      body = @transport.delete("/communities/#{esc(slug)}/word-filter/entries", { "value" => value.to_s })
      unwrap(body, "entries")
    end

    # @return [Array<String>]
    def room_word_filter_entries(slug, room_key)
      list("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/word-filter/entries", "entries")
    end

    # @see #replace_word_filter_entries
    # @return [Array<String>]
    def replace_room_word_filter_entries(slug, room_key, entries)
      body = @transport.put("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/word-filter/entries",
                            { "entries" => Array(entries) })
      unwrap(body, "entries")
    end

    # @see #remove_word_filter_entry
    # @return [Array<String>]
    def remove_room_word_filter_entry(slug, room_key, value)
      body = @transport.delete("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/word-filter/entries",
                               { "value" => value.to_s })
      unwrap(body, "entries")
    end

    # @return [Array<Models::FaqEntry>]
    def faq_entries(slug) = list_of(Models::FaqEntry, "/communities/#{esc(slug)}/faq/entries", "entries")

    # Add a community-wide FAQ entry, minting its stable id.
    #
    # @param trigger_type ["command", "keyword"] "command" fires +trigger+ on
    #   `/name` or `!name`; anything else posts it as a keyword alongside a
    #   matching message
    # @return [Models::FaqEntry] the entry that was added
    def add_faq_entry(slug, trigger:, response:, trigger_type:)
      Models::FaqEntry.from_h(
        @transport.post("/communities/#{esc(slug)}/faq/entries",
                        { "trigger" => trigger, "response" => response, "trigger_type" => trigger_type })
      )
    end

    # Remove a community-wide FAQ entry, addressed by the id {#add_faq_entry}
    # minted, never by array position.
    #
    # @return [Array<Models::FaqEntry>] the surviving entries
    def remove_faq_entry(slug, id)
      body = @transport.delete("/communities/#{esc(slug)}/faq/entries/#{esc(id)}")
      Models::FaqEntry.array(unwrap(body, "entries"))
    end

    # @return [Array<Models::FaqEntry>]
    def room_faq_entries(slug, room_key)
      list_of(Models::FaqEntry, "/communities/#{esc(slug)}/rooms/#{esc(room_key)}/faq/entries", "entries")
    end

    # @see #add_faq_entry
    # @return [Models::FaqEntry]
    def add_room_faq_entry(slug, room_key, trigger:, response:, trigger_type:)
      Models::FaqEntry.from_h(
        @transport.post("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/faq/entries",
                        { "trigger" => trigger, "response" => response, "trigger_type" => trigger_type })
      )
    end

    # @see #remove_faq_entry
    # @return [Array<Models::FaqEntry>]
    def remove_room_faq_entry(slug, room_key, id)
      body = @transport.delete("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/faq/entries/#{esc(id)}")
      Models::FaqEntry.array(unwrap(body, "entries"))
    end

    # @return [Array<Models::JoinLink>]
    def join_links(slug) = list_of(Models::JoinLink, "/communities/#{esc(slug)}/join-links", "join_links")

    # Replace the community's public join-link list outright. Each entry is
    # normalized on the way in; a row with no usable url is silently dropped
    # rather than refused.
    #
    # @param join_links [Array<Hash>] each needing "url", plus optional
    #   "platform" and "label"
    # @return [Array<Models::JoinLink>] the list as it stands afterwards
    def replace_join_links(slug, join_links)
      body = @transport.put("/communities/#{esc(slug)}/join-links", { "join_links" => Array(join_links) })
      Models::JoinLink.array(unwrap(body, "join_links"))
    end

    # @return [Array<Models::JoinLink>]
    def room_join_links(slug, room_key)
      list_of(Models::JoinLink, "/communities/#{esc(slug)}/rooms/#{esc(room_key)}/join-links", "join_links")
    end

    # @see #replace_join_links
    # @return [Array<Models::JoinLink>]
    def replace_room_join_links(slug, room_key, join_links)
      body = @transport.put("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/join-links",
                            { "join_links" => Array(join_links) })
      Models::JoinLink.array(unwrap(body, "join_links"))
    end

    # ------------------------------------------------------------------
    # Platform wiring
    # ------------------------------------------------------------------

    # Read-only for any key. There are no write verbs over the API yet.
    #
    # @return [Array<Models::PlatformConnection>]
    def platform_connections(slug)
      list_of(Models::PlatformConnection, "/communities/#{esc(slug)}/platform-connections", "platform_connections")
    end

    # @return [Array<Models::IrcNetwork>]
    def irc_networks(slug) = list_of(Models::IrcNetwork, "/communities/#{esc(slug)}/irc-networks", "irc_networks")

    # @return [Models::IrcNetwork]
    def irc_network(slug, name)
      Models::IrcNetwork.from_h(@transport.get("/communities/#{esc(slug)}/irc-networks/#{esc(name)}"))
    end

    # @return [Array<Models::FluxerInstance>]
    def fluxer_instances(slug)
      list_of(Models::FluxerInstance, "/communities/#{esc(slug)}/fluxer-instances", "fluxer_instances")
    end

    # @return [Models::FluxerInstance]
    def fluxer_instance(slug, label)
      Models::FluxerInstance.from_h(@transport.get("/communities/#{esc(slug)}/fluxer-instances/#{esc(label)}"))
    end

    # ------------------------------------------------------------------
    # Guest invites and events
    # ------------------------------------------------------------------

    # No token is ever present in one of these. Only a digest is stored, and
    # the raw token is shown to the inviter once, at issuance.
    #
    # @return [Array<Models::GuestInvite>]
    def guest_invites(slug) = list_of(Models::GuestInvite, "/communities/#{esc(slug)}/guest-invites", "guest_invites")

    # @return [Models::GuestInvite]
    def guest_invite(slug, id)
      Models::GuestInvite.from_h(@transport.get("/communities/#{esc(slug)}/guest-invites/#{esc(id)}"))
    end

    # Upcoming and not cancelled, which is a narrower set than the events
    # table holds. Reading a past or cancelled event means asking for it by id
    # through {#event}.
    #
    # @return [Array<Models::Event>]
    def room_events(slug, room_key)
      list_of(Models::Event, "/communities/#{esc(slug)}/rooms/#{esc(room_key)}/events", "events")
    end

    # Note the path: an event is addressed on the community even though the
    # list route above is room-scoped.
    #
    # @return [Models::Event]
    def event(slug, id) = Models::Event.from_h(@transport.get("/communities/#{esc(slug)}/events/#{esc(id)}"))

    # ------------------------------------------------------------------
    # Onboarding
    # ------------------------------------------------------------------
    #
    # Administrator only, every one of them, and named by no slug: a pending
    # space belongs to no community until somebody approves it, so there is
    # nothing for a developer key to be scoped to and a space awaiting a
    # decision may turn out to be somebody else's.

    # Spaces the bot was added to that no community owns yet, the review
    # queue. A space the bot is added to posts a one-time notice, waits here
    # for a decision, and leaves on its own if none arrives.
    #
    # @param state ["pending", "denied", "all", nil] nil uses the API's
    #   default, pending
    # @return [Array<Models::PendingSpace>]
    def admin_pending_spaces(state: nil)
      list_of(Models::PendingSpace, "/admin/pending-spaces", "pending_spaces", query: compact(state: state))
    end

    # @return [Models::PendingSpace]
    def admin_pending_space(id) = Models::PendingSpace.from_h(@transport.get("/admin/pending-spaces/#{esc(id)}"))

    # Drop a refused space, so it may be reviewed again. A refused row stays
    # as a standing refusal, so the same space rejoining is turned away
    # without a second review until it is cleared this way.
    #
    # Only a refused row can be cleared. Raises {ValidationFailed} for one
    # still awaiting a decision, which is settled through
    # {#admin_approve_pending_space} or {#admin_reject_pending_space} instead.
    #
    # @return [true]
    def admin_clear_pending_space(id)
      @transport.delete("/admin/pending-spaces/#{esc(id)}")
      true
    end

    # Accept a space onto an existing community, or as a new one. Writes the
    # platform connection and nothing else: no room, no channel mapping, no
    # feature. The community stays dormant until somebody maps a channel
    # into a room, so accepting a space never turns anything on by itself.
    #
    # A space already decided raises {ValidationFailed}, and no second
    # decision is recorded.
    #
    # @param community [String, nil] an existing community's slug to accept
    #   the space onto. Give this or new_community_name:, never neither.
    # @param new_community_name [String, nil] a name for a brand new
    #   community to create for the space. Its slug is derived and made unique.
    # @param make_operator [Boolean, nil] promote whoever added the bot to
    #   operator of the community. Does nothing when the space's own
    #   "can_make_operator" is false.
    # @return [Models::PendingSpaceDecision] the space, and the community it
    #   now belongs to
    def admin_approve_pending_space(id, community: nil, new_community_name: nil, make_operator: nil)
      Models::PendingSpaceDecision.from_h(
        @transport.post("/admin/pending-spaces/#{esc(id)}/approve",
                        compact(community: community, new_community_name: new_community_name,
                                make_operator: make_operator))
      )
    end

    # Refuse a space and leave it. The decision is recorded at once; the
    # departure itself is scheduled for whichever bot process is running and
    # lands shortly afterwards.
    #
    # The row stays as a standing refusal, so the same space rejoining is
    # turned away without a second review, until {#admin_clear_pending_space}.
    #
    # @return [Models::PendingSpace]
    def admin_reject_pending_space(id)
      Models::PendingSpace.from_h(@transport.post("/admin/pending-spaces/#{esc(id)}/reject"))
    end

    # Which pending spaces look like they belong to this community, guessed
    # by comparing the space's name against the community's name and slug.
    # Nothing here writes and nothing here decides: a suggestion is accepted
    # by approving that pending space.
    #
    # The matching is deliberately mean, since attaching a stranger's group
    # to somebody's community is far worse than showing no suggestion at
    # all. A space that matches two communities is suggested to neither.
    #
    # @return [Array<Models::SpaceSuggestion>]
    def admin_space_suggestions(slug)
      list_of(Models::SpaceSuggestion, "/admin/communities/#{esc(slug)}/space-suggestions", "suggestions")
    end

    # ------------------------------------------------------------------
    # Alerts
    # ------------------------------------------------------------------

    # What this community's scripts raised for its operators, newest first.
    #
    # Returns {Models::AlertList} rather than the bare array, because `unseen`
    # comes back with it and counts everything outstanding rather than
    # everything on this page. Splitting them would cost a second request for a
    # number already in hand.
    #
    # Reachable with a developer key, unlike the script routes themselves.
    #
    # Anything older than the retention window is gone whether or not the
    # deployment has swept, so an empty list means there is nothing to see and
    # not that housekeeping is behind.
    #
    # @param limit [Integer, nil] how many to return. Clamped rather than
    #   refused, so asking for more than a community can hold is not an error.
    # @return [Models::AlertList]
    def alerts(slug, limit: nil)
      Models::AlertList.from_h(@transport.get("/communities/#{esc(slug)}/alerts", query: compact(limit: limit)))
    end

    # Mark one alert seen and return it as it stands afterwards.
    #
    # Marking one that was already seen keeps its original timestamp and is not
    # an error: the state you asked for is the state it is in. An id belonging
    # to another community raises {NotFound}, the same as one that never
    # existed.
    #
    # @return [Models::Alert]
    def mark_alert_seen(slug, id)
      Models::Alert.from_h(@transport.post("/communities/#{esc(slug)}/alerts/#{esc(id)}/seen"))
    end

    # Mark every outstanding alert seen, for coming back to a backlog already
    # dealt with somewhere else. The count is how many changed, and is zero
    # when there was nothing outstanding.
    #
    # @return [Integer] how many alerts were marked seen
    def mark_all_alerts_seen(slug)
      unwrap(@transport.post("/communities/#{esc(slug)}/alerts/seen"), "marked")
    end

    # ------------------------------------------------------------------
    # Room participation
    # ------------------------------------------------------------------
    #
    # A room game, trivia or a poll among them, is a script's own concept:
    # rubotty holds no list of what a session may be called and these two
    # routes read and close whatever is open, exactly as a script's own
    # session() and close_session() calls would.

    # A room's open session and its standings.
    #
    # @return [Models::RoomParticipation] `session` is nil when nothing is
    #   running in the room; `standings` is always an array, empty when there
    #   is no session or nobody has answered yet
    def room_participation(slug, room_key)
      Models::RoomParticipation.from_h(
        @transport.get("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/participation")
      )
    end

    # Close a room's open session, and whatever round is open inside it.
    # Raises {ValidationFailed} when nothing is running in the room.
    #
    # @return [true]
    def close_room_participation(slug, room_key)
      unwrap(@transport.post("/communities/#{esc(slug)}/rooms/#{esc(room_key)}/participation/close"), "closed")
    end

    # ------------------------------------------------------------------
    # Administrator only
    # ------------------------------------------------------------------

    # Platform accounts, which belong to the deployment rather than to any one
    # community. `settings` carries env var names and flags, never a secret.
    #
    # @return [Array<Models::Account>]
    def admin_accounts = list_of(Models::Account, "/admin/accounts", "accounts")

    # @return [Models::Account]
    def admin_account(adapter, name)
      Models::Account.from_h(@transport.get("/admin/accounts/#{esc(adapter)}/#{esc(name)}"))
    end

    # public_id, scope, label and usage. A token is never returned, since only
    # its digest is stored.
    #
    # @return [Array<Models::ApiKey>]
    def admin_api_keys = list_of(Models::ApiKey, "/admin/api-keys", "api_keys")

    # Every deployment-wide connection to an outside service this deployment
    # knows about, e.g. LibreTranslate, configured or not. One nobody has set
    # up yet still appears, with "url" null and "api_key_set" false. Read
    # only: every write goes through the dashboard, which is also where a
    # connection is tested.
    #
    # @return [Array<Models::Integration>]
    def admin_integrations = list_of(Models::Integration, "/admin/integrations", "integrations")

    # 404 only for a name this deployment has never heard of. A known
    # integration nobody has configured yet still answers, with "url" null
    # and "api_key_set" false.
    #
    # @return [Models::Integration]
    def admin_integration(name) = Models::Integration.from_h(@transport.get("/admin/integrations/#{esc(name)}"))

    # ------------------------------------------------------------------
    # Viewers, deployment wide
    # ------------------------------------------------------------------
    #
    # A viewer reads every community in the deployment and changes nothing
    # anywhere. Administrator only on every verb, because the dimension spans
    # the whole deployment: a developer key confined to one community must
    # never be able to hand out oversight of the rest. {#community_viewers}
    # and its neighbours are the community-scoped equivalent.

    # Two lists. `viewers` are the granted rows, which {#admin_revoke_viewer}
    # can remove; `baked_in` are the handles the deployment ships with, which
    # it cannot. Resolution is the union of the two.
    #
    # @return [Models::ViewerRoster]
    def admin_viewers = Models::ViewerRoster.from_h(@transport.get("/admin/viewers"))

    # Grant viewer status to a handle. Named by the platform handle a person
    # owns, never by a display name, which anyone can set to anything. On a
    # federated platform the fully qualified id is the handle.
    #
    # Idempotent: granting a handle that already holds it answers the
    # existing entry. A handle the deployment already ships with raises
    # {ValidationFailed}, since the resulting entry would look revocable and
    # would not be.
    #
    # native_id binds the grant to a stable account. When omitted, the API must
    # resolve the handle to one known identity or refuse it.
    # @return [Models::Viewer]
    def admin_grant_viewer(adapter:, handle:, label: nil, native_id: nil)
      Models::Viewer.from_h(
        @transport.post("/admin/viewers", compact(adapter: adapter, handle: handle, label: label, native_id: native_id))
      )
    end

    # Take viewer status back. Raises {ValidationFailed} when the deployment
    # also ships with that handle: removing the entry would read as a
    # revocation while the shipped floor kept handing the same person every
    # community.
    #
    # @return [true]
    def admin_revoke_viewer(id)
      @transport.delete("/admin/viewers/#{esc(id)}")
      true
    end

    # Open requests to read every community, oldest first. Filed by DMing the
    # bot. Only an administrator decides one, which is the one place this
    # differs from an operator request: an operator request is decided by an
    # operator of that community, and this one spans them all.
    #
    # @return [Array<Models::ViewerRequest>]
    def admin_viewer_requests = list_of(Models::ViewerRequest, "/admin/viewer-requests", "viewer_requests")

    # Grant a pending viewer request. The request is marked approved and the
    # requester's handle is granted in the same call.
    #
    # @return [Models::ViewerRequestDecision] the decided request, and the
    #   viewer it produced
    def admin_approve_viewer_request(id)
      Models::ViewerRequestDecision.from_h(@transport.post("/admin/viewer-requests/#{esc(id)}/approve"))
    end

    # Refuse a pending viewer request. Grants nothing. A denied request does
    # not block a later one, so somebody refused today can ask again.
    #
    # @return [Models::ViewerRequest]
    def admin_deny_viewer_request(id)
      body = @transport.post("/admin/viewer-requests/#{esc(id)}/deny")
      Models::ViewerRequest.from_h(unwrap(body, "request"))
    end

    # ------------------------------------------------------------------
    # Tokens, deployment wide
    # ------------------------------------------------------------------

    # Every token this deployment has, community scoped ones included, newest
    # first, since an administrator is who has to be able to account for all
    # of them. The token strings themselves are not here and cannot be: only
    # their digests are kept. {#community_auth_tokens} narrows to one.
    #
    # @return [Array<Models::AuthToken>]
    def admin_auth_tokens = list_of(Models::AuthToken, "/admin/auth-tokens", "auth_tokens")

    # Mint a token that hands over reading every community when redeemed with
    # the bot's `/auth` command.
    #
    # Administrator only, because the token IS the grant: it is taken in
    # advance, so anything a developer key could mint here would go around
    # the check on handing that role over directly. A token minted for one
    # community belongs on {#mint_community_auth_token} instead.
    #
    # @param ttl_seconds [Integer, nil] how long it stays redeemable.
    #   Defaults to a day, and a fortnight is the most it may be.
    # @return [Models::IssuedAuthToken] carries `token`, shown here and nowhere else
    def admin_mint_auth_token(ttl_seconds: nil, label: nil)
      Models::IssuedAuthToken.from_h(@transport.post("/admin/auth-tokens", compact(ttl_seconds: ttl_seconds, label: label)))
    end

    # Take a token back before it is used. Raises {ValidationFailed} once the
    # token has been redeemed: the role it carried is already granted by
    # then, so revoking it would say something untrue.
    #
    # @return [true]
    def admin_revoke_auth_token(public_id)
      @transport.delete("/admin/auth-tokens/#{esc(public_id)}")
      true
    end

    # The same analytics overview the dashboard shows, for the default window.
    #
    # @return [Models::Stats] `window`, `since` and `now` are real accessors;
    #   the rest, one sub-object each for moderation, members, messages and
    #   the like, are deliberately left unmodelled and reached through
    #   `sections`, since a fixed accessor set here would describe today's
    #   aggregates rather than whichever release a deployment is running.
    def admin_community_stats(slug) = Models::Stats.from_h(@transport.get("/admin/communities/#{esc(slug)}/stats"))

    # Build and runtime facts, keyed by process ("web", "bot", or both).
    #
    # The bot reports its own version and commit rather than this being
    # inferred from the web process, which is what makes the answer useful
    # when one container is still running an older deploy. An unreachable bot
    # says so under `reachable` and `error` instead of going missing.
    #
    # @param source ["web", "bot", "all", nil] nil uses the API's default, web
    # @return [Models::DebugInfo] `web` and `bot` are each nil when `source:`
    #   did not ask for that process
    def admin_debug_info(source: nil)
      Models::DebugInfo.from_h(@transport.get("/admin/debug/info", query: compact(source: source)))
    end

    # Recent log lines. With source "all" both processes' entries merge into
    # one timestamp-sorted list under `entries`, each tagged with where it
    # came from, and a source that could not be read is named under `errors`.
    # The whole answer is returned rather than just the entries, because a
    # caller that ignores `errors` can read a partial answer as a complete one.
    #
    # Each process keeps its lines in a bounded in-memory buffer, so this is a
    # live tail and a restart empties it.
    #
    # @param source ["web", "bot", "all", nil] nil uses the API's default, web
    # @param level [String, nil] this level and anything more severe
    # @param limit [Integer, nil]
    # @return [Models::DebugLog]
    def admin_debug_logs(source: nil, level: nil, limit: nil)
      Models::DebugLog.from_h(
        @transport.get("/admin/debug/logs", query: compact(source: source, level: level, limit: limit))
      )
    end

    # A read-only sweep for a gap the paced backfill's own resume point
    # cannot reach. Runs on the bot process, the only one holding a live
    # platform connection, over the same internal hop {#admin_debug_logs}
    # and {#admin_debug_info} already use.
    #
    # Every backfill-capable channel is swept over its full lookback window
    # with no resume point, and each candidate message is classified as
    # already claimed by the relay ledger, one of this bridge's own relayed
    # copies, older than the safe horizon, or a genuine gap. Nothing here
    # relays, posts or claims anything; it only reports what a real backfill
    # would find. A finding names only the source endpoint, the platform's
    # own message id and its timestamp, never the message itself.
    #
    # The whole answer is returned rather than just the channels, because an
    # unreachable bot is reported under `errors` and a caller ignoring it
    # would read a partial answer as a complete one.
    #
    # @return [Models::BackfillGapsReport] `channels`, worst (most gaps)
    #   first, and `errors` when the bot process could not be reached
    def admin_debug_backfill_gaps
      Models::BackfillGapsReport.from_h(@transport.get("/admin/debug/backfill-gaps"))
    end

    # ------------------------------------------------------------------
    # Scripts, the endpoints they call, and the numbers they record
    # ------------------------------------------------------------------
    #
    # Administrator only, every one of them. A script is code the deployment
    # runs and an endpoint decides which hosts it may reach, so neither is
    # reachable with a developer key.

    # Live scripts. The archive is a separate call, so this never mixes the two.
    #
    # @return [Array<Models::Script>]
    def admin_scripts(slug) = list_of(Models::Script, "/admin/communities/#{esc(slug)}/scripts", "scripts")

    # What {#admin_archive_script} moved aside. Restorable.
    #
    # @return [Array<Models::Script>]
    def admin_archived_scripts(slug)
      list_of(Models::Script, "/admin/communities/#{esc(slug)}/scripts/archived", "scripts")
    end

    # @return [Models::Script]
    def admin_script(slug, id) = Models::Script.from_h(@transport.get("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}"))

    # Create one. It arrives switched off and unchecked: switching it on is a
    # separate call, so nothing half-written starts running on live traffic.
    #
    # +condition+ is sent as "trigger_type", which is what the API names it on
    # the way in even though it answers with "condition". The inconsistency is
    # the API's; this keeps the outgoing name matching the wire and the Ruby
    # name matching what comes back.
    #
    # @param kind ["processor", "command", "callback"]
    # @param language [String] one of {#admin_scripting_capabilities}' languages
    # @param condition [String] one of its conditions
    # @param trigger_config [Hash] the fields that condition takes
    # @param yaml_data [String, nil] the script's own YAML data file, read
    #   back with `rubotty.yaml_data()`. Parsed on arrival, so a document that
    #   will not parse raises {ValidationFailed} instead of reaching the
    #   script; it has to be a set of keys or a list, capped at the size
    #   {#admin_scripting_capabilities} reports.
    # @return [Models::Script]
    def admin_create_script(slug, name:, source:, kind: "processor", language: "lua",
                            condition: "always", trigger_config: nil, yaml_data: nil)
      Models::Script.from_h(
        @transport.post("/admin/communities/#{esc(slug)}/scripts",
                        script_body(name: name, source: source, kind: kind, language: language,
                                    condition: condition, trigger_config: trigger_config, yaml_data: yaml_data))
      )
    end

    # Edit one. Every keyword is optional and anything left out keeps the value
    # the script already has, so changing the source does not blank the trigger.
    #
    # @return [Models::Script]
    def admin_update_script(slug, id, name: nil, source: nil, kind: nil, language: nil,
                            condition: nil, trigger_config: nil, yaml_data: nil)
      body = script_body(name: name, source: source, kind: kind, language: language,
                         condition: condition, trigger_config: trigger_config, yaml_data: yaml_data)
      raise ArgumentError, "pass at least one field to change" if body.empty?

      Models::Script.from_h(@transport.patch("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}", body))
    end

    # Archive rather than destroy, which is why {#admin_restore_script} exists.
    #
    # @return [true]
    def admin_archive_script(slug, id)
      @transport.delete("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}")
      true
    end

    # Bring an archived script back, still switched off.
    #
    # @return [Models::Script]
    def admin_restore_script(slug, id)
      Models::Script.from_h(@transport.post("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}/restore"))
    end

    # Compile and smoke-test without switching anything on.
    #
    # Answers rather than raises when a script fails, because a script that
    # does not compile is a normal answer to this question. `ok` is the
    # boolean, and `problems` is an empty array when it passed and the
    # collected reasons as one string when it did not.
    #
    # @return [Models::ScriptVerification]
    def admin_verify_script(slug, id)
      Models::ScriptVerification.from_h(@transport.post("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}/verify"))
    end

    # Let it run on live traffic. Raises {ValidationFailed} unless it has
    # passed {#admin_verify_script} against exactly its current text.
    #
    # @return [Models::Script]
    def admin_enable_script(slug, id)
      Models::Script.from_h(@transport.post("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}/enable"))
    end

    # @return [Models::Script]
    def admin_disable_script(slug, id)
      Models::Script.from_h(@transport.post("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}/disable"))
    end

    # What went wrong the last few times this script ran on live traffic.
    #
    # The one to poll if you are automating a health check. `errors` is a short
    # ring of recent failures, newest first, and it survives an edit, so a
    # script fixed an hour ago still shows what it was doing before.
    # `consecutive_failures` counts the current streak and resets on a clean
    # run; a script that fails often enough is switched off, which shows as
    # `disabled_at` and `disabled_reason` rather than only as a high count.
    #
    # A script that has never failed answers with the same shape, empty. That
    # is the healthy answer, not a {NotFound}.
    #
    # Each message is truncated where it was recorded, since a script can build
    # an error out of text it was handed.
    #
    # @return [Models::ScriptErrors]
    def admin_script_errors(slug, id)
      Models::ScriptErrors.from_h(@transport.get("/admin/communities/#{esc(slug)}/scripts/#{esc(id)}/errors"))
    end

    # What a script may be on this deployment: the kinds, the trigger
    # conditions, the languages installed here and the limits enforced.
    #
    # Worth reading rather than hardcoding. Which languages are on offer
    # depends on which transpilers are present on the host, so the answer
    # differs between deployments and can change on a redeploy.
    #
    # @return [Models::ScriptingCapabilities]
    def admin_scripting_capabilities
      Models::ScriptingCapabilities.from_h(@transport.get("/admin/scripting/capabilities"))
    end

    # The named outbound endpoints a script may call.
    #
    # An administrator writes down what a name means and a script only ever
    # knows the name. Headers are never returned, only `has_headers`: an
    # endpoint carries an API key, and the point of keeping it here is that it
    # is not readable from anywhere a script author can reach.
    #
    # @return [Array<Models::ScriptEndpoint>]
    def admin_script_endpoints(slug)
      list_of(Models::ScriptEndpoint, "/admin/communities/#{esc(slug)}/endpoints", "endpoints")
    end

    # @return [Models::ScriptEndpoint]
    def admin_script_endpoint(slug, id)
      Models::ScriptEndpoint.from_h(@transport.get("/admin/communities/#{esc(slug)}/endpoints/#{esc(id)}"))
    end

    # @param headers [Hash, String, nil] a mapping, or text with one
    #   "Name: value" per line. Write only, never echoed back.
    # @param query_params [Hash, String, nil] the same two forms
    # @param allow_sync [Boolean] whether a script may wait for the answer,
    #   holding the message up while it does
    # @return [Models::ScriptEndpoint]
    def admin_create_script_endpoint(slug, name:, url:, http_method: nil, description: nil,
                                     headers: nil, query_params: nil, allow_sync: nil,
                                     enabled: nil, timeout_seconds: nil, cache_seconds: nil)
      Models::ScriptEndpoint.from_h(
        @transport.post(
          "/admin/communities/#{esc(slug)}/endpoints",
          endpoint_body(name: name, url: url, http_method: http_method, description: description,
                        headers: headers, query_params: query_params, allow_sync: allow_sync,
                        enabled: enabled, timeout_seconds: timeout_seconds, cache_seconds: cache_seconds)
        )
      )
    end

    # Every keyword optional; anything left out keeps its current value.
    #
    # @return [Models::ScriptEndpoint]
    def admin_update_script_endpoint(slug, id, name: nil, url: nil, http_method: nil, description: nil,
                                     headers: nil, query_params: nil, allow_sync: nil,
                                     enabled: nil, timeout_seconds: nil, cache_seconds: nil)
      body = endpoint_body(name: name, url: url, http_method: http_method, description: description,
                           headers: headers, query_params: query_params, allow_sync: allow_sync,
                           enabled: enabled, timeout_seconds: timeout_seconds, cache_seconds: cache_seconds)
      raise ArgumentError, "pass at least one field to change" if body.empty?

      Models::ScriptEndpoint.from_h(@transport.patch("/admin/communities/#{esc(slug)}/endpoints/#{esc(id)}", body))
    end

    # Removed outright, unlike a script: an endpoint is configuration rather
    # than authored work. A script naming it afterwards fails at the call.
    #
    # @return [true]
    def admin_delete_script_endpoint(slug, id)
      @transport.delete("/admin/communities/#{esc(slug)}/endpoints/#{esc(id)}")
      true
    end

    # The counters scripts recorded. Read only over the API: recording one is
    # something a script does, not something a client does on its behalf.
    #
    # @return [Hash{String => Array<Models::ScriptStatRow>}] counter name to
    #   its rows. Stays a Hash at the top level since a counter's name is
    #   whatever a script chose to call it, not a fixed set this gem could
    #   enumerate.
    def admin_script_stats(slug)
      body = @transport.get("/admin/communities/#{esc(slug)}/script-stats")
      raise MalformedResponse, "expected \"stats\" in the response, got #{body.keys.inspect}" unless body.key?("stats")

      body.fetch("stats").transform_values { |rows| Models::ScriptStatRow.array(rows) }
    end

    # ------------------------------------------------------------------
    # Webhooks
    # ------------------------------------------------------------------
    #
    # Administrator only. A subscription is a standing instruction to forward
    # what is said in a community's rooms to an address outside the deployment,
    # and it carries a signing secret.

    # Every subscription, newest first. A subscription is addressed by its
    # `public_id`; the signing secret is never in one of these.
    #
    # @return [Array<Models::Webhook>]
    def admin_webhooks(slug) = list_of(Models::Webhook, "/admin/communities/#{esc(slug)}/webhooks", "webhooks")

    # @return [Models::Webhook]
    def admin_webhook(slug, public_id)
      Models::Webhook.from_h(@transport.get("/admin/communities/#{esc(slug)}/webhooks/#{esc(public_id)}"))
    end

    # Create one. This response and {#admin_rotate_webhook_secret}'s are the
    # only two that carry `secret`, so keep it here: it is what signs every
    # delivery and it is not readable back from anywhere else.
    #
    # @param event_types [Array<String>, String] which events to receive. An
    #   unknown one raises {ValidationFailed} at creation, which is the only
    #   moment anybody is watching.
    # @param room_key [String, nil] one room, or nil for every room
    # @return [Models::WebhookWithSecret]
    def admin_create_webhook(slug, url:, event_types:, room_key: nil, label: nil)
      body = { "url" => url.to_s, "event_types" => Array(event_types).join(",") }
      body["room_key"] = room_key.to_s unless room_key.nil?
      body["label"] = label.to_s unless label.nil?
      Models::WebhookWithSecret.from_h(@transport.post("/admin/communities/#{esc(slug)}/webhooks", body))
    end

    # Mint a new signing secret, keeping the old one valid for +overlap+
    # seconds. During the overlap a delivery carries both signatures, so a
    # subscriber can deploy the new secret whenever suits them rather than at
    # this exact instant. Pass 0 to retire the old secret immediately, which is
    # what a leaked secret needs.
    #
    # @param overlap [Integer, nil] seconds, defaulting to a day at the far end
    # @return [Models::WebhookWithSecret]
    def admin_rotate_webhook_secret(slug, public_id, overlap: nil)
      Models::WebhookWithSecret.from_h(
        @transport.post("/admin/communities/#{esc(slug)}/webhooks/#{esc(public_id)}/rotate",
                        overlap.nil? ? nil : { "overlap" => overlap })
      )
    end

    # @return [true]
    def admin_delete_webhook(slug, public_id)
      @transport.delete("/admin/communities/#{esc(slug)}/webhooks/#{esc(public_id)}")
      true
    end

    # What happened to every attempt at sending one, newest first, which is
    # the half of this a subscriber cannot see from their own end.
    #
    # @param webhook [String, nil] narrow to one subscription's public_id
    # @param status [String, nil] "queued", "delivered" or "failed"
    # @param limit [Integer, nil]
    # @return [Array<Models::WebhookDelivery>]
    def admin_webhook_deliveries(slug, webhook: nil, status: nil, limit: nil)
      body = @transport.get("/admin/communities/#{esc(slug)}/webhook-deliveries",
                            query: compact(webhook: webhook, status: status, limit: limit))
      unless body.key?("deliveries")
        raise MalformedResponse, "expected \"deliveries\" in the response, got #{body.keys.inspect}"
      end

      Models::WebhookDelivery.array(body.fetch("deliveries"))
    end

    # ------------------------------------------------------------------
    # Backfill proposals
    # ------------------------------------------------------------------
    #
    # Administrator only, and named by no slug: one sweep writes proposals
    # across a community's channels, and accepting one posts into live rooms.
    # A gap larger than a channel's own auto-relay limit is written down
    # rather than sent, and goes out only when somebody accepts it.

    # The proposals in the state asked for, freshest first.
    #
    # Every row carries the counts the sweep recorded. `ours` is the one to
    # read first: it is how many of the fetched messages the sweep
    # recognised as this bridge's own relayed copies and skipped. A zero
    # there on a channel that has bridged for months means the ownership
    # check is not working, and accepting anything would push those copies
    # back into a live room.
    #
    # @param state ["pending", "approved", "rejected", "expired", "relayed",
    #   "all", nil] nil uses the API's default, pending
    # @return [Array<Models::BackfillProposal>]
    def admin_backfill_proposals(state: nil)
      list_of(Models::BackfillProposal, "/admin/backfill-proposals", "backfill_proposals", query: compact(state: state))
    end

    # Read one proposal and the messages it would send, exactly as an accept
    # would relay them: nothing is recomputed here or at accept time, so what
    # is read is what goes.
    #
    # A preview is kept only while the proposal still needs one. Once it is
    # rejected, expires, or has had its accepted list relayed, the previews
    # are deleted and the row keeps the counts alone; that case answers
    # `items_pruned` true with `items_note` saying so, rather than an empty
    # list that would read as "the sweep was going to send nothing".
    #
    # @return [Models::BackfillProposalDetail]
    def admin_backfill_proposal(id)
      Models::BackfillProposalDetail.from_h(@transport.get("/admin/backfill-proposals/#{esc(id)}"))
    end

    # Accept one channel's list, and send it. Stamps the proposal and hands
    # the stored list to the bot process, which is the only one holding the
    # platform connections that can send. The send itself is paced and runs
    # there, so this answers as soon as the bot has taken the list rather
    # than when the last message has landed.
    #
    # Only a proposal still waiting on a decision can be accepted. One
    # already decided, or one that has run out of time, raises
    # {ValidationFailed} and no second decision is recorded.
    #
    # @return [Models::BackfillProposalApproval] `relaying` false means
    #   accepted but nothing is going out, with the reason under the `errors`
    #   this carries only then
    def admin_approve_backfill_proposal(id)
      Models::BackfillProposalApproval.from_h(@transport.post("/admin/backfill-proposals/#{esc(id)}/approve"))
    end

    # Refuse one channel's list. Nothing from that channel is sent, and the
    # previews go with the decision. The row stays, with its counts, so the
    # history still says what was proposed and what happened to it.
    #
    # Only a proposal still waiting on a decision can be refused; one already
    # decided raises {ValidationFailed}.
    #
    # @return [Models::BackfillProposal]
    def admin_reject_backfill_proposal(id)
      body = @transport.post("/admin/backfill-proposals/#{esc(id)}/reject")
      Models::BackfillProposal.from_h(unwrap(body, "backfill_proposal"))
    end

    # ------------------------------------------------------------------
    # Files
    # ------------------------------------------------------------------
    #
    # Administrator only. Each of these either mints a link to bytes the
    # deployment is holding, moves one, or invalidates one.
    #
    # The UUID naming a file is never stored by the deployment, only a digest
    # of it, so two things follow and they shape this whole group. A listing
    # cannot give you a UUID, and a new link cannot be conjured for a file you
    # can only see: {#admin_rotate_file_link} takes the UUID you already hold.
    # Lose a UUID and the file is unreachable until it expires.

    # Every file this community is holding, newest first. No entry carries a
    # UUID or a link. Each is identified by `id`, which is what
    # {#admin_file} takes.
    #
    # @return [Array<Models::FileRecord>]
    def admin_files(slug) = list_of(Models::FileRecord, "/admin/communities/#{esc(slug)}/files", "files")

    # @return [Models::FileRecord]
    def admin_file(slug, id)
      Models::FileRecord.from_h(@transport.get("/admin/communities/#{esc(slug)}/files/#{esc(id)}"))
    end

    # Store a file and receive the UUID naming it, along with the download URL
    # built from that UUID.
    #
    # KEEP THE UUID. It comes back here and from a rotation and nowhere else,
    # and without it the file cannot be downloaded, rotated or expired.
    #
    # The file is streamed rather than read into memory, so its size is bounded
    # only by what the community accepts. Over that raises {ApiError} with a
    # status of 413. A community not accepting files at all, and a request with
    # no file, both raise {ValidationFailed}. A deployment with no file storage
    # raises {ApiError} with a status of 503.
    #
    # The community's own retention applies, so `expires_at` in the answer is
    # when this file will really be deleted.
    #
    # @param file [String, IO] a path, or any object answering read
    # @param filename [String, nil] the name to record. Required when +file+ is
    #   an IO with no path of its own.
    # @param content_type [String, nil]
    # @param room_key [String, nil] which room the file belongs to
    # @return [Models::FileRecordWithLink]
    def admin_upload_file(slug, file, filename: nil, content_type: nil, room_key: nil)
      return upload_path(slug, file, filename, content_type, room_key) if file.is_a?(String)
      raise ArgumentError, "file must be a path or an object answering read" unless file.respond_to?(:read)

      name = filename || (file.respond_to?(:path) ? File.basename(file.path.to_s) : nil)
      raise ArgumentError, "filename: is required when the file is not a path" if name.to_s.empty?

      send_upload(slug, file, name, content_type, room_key)
    end

    # Replace a file's link with a new one, retiring the old.
    #
    # Give it the UUID you hold; you get a different one back and the old link
    # stops working at once. That is what a leaked link needs, and it is the
    # only shape this can take, since the deployment cannot read its own key
    # back to mint a second link on its own.
    #
    # This re-encrypts the file rather than updating a record, so it takes time
    # in proportion to the file's size. The retention is not extended: rotating
    # changes who can reach a file, not how long it is kept.
    #
    # A UUID naming nothing live, and one naming another community's file, both
    # raise {NotFound} identically.
    #
    # @return [Models::FileRecordWithLink] the file, with the NEW uuid and url
    def admin_rotate_file_link(slug, uuid)
      Models::FileRecordWithLink.from_h(
        @transport.post("/admin/communities/#{esc(slug)}/files/rotate", { "uuid" => uuid.to_s })
      )
    end

    # Mark a file for deletion.
    #
    # The link stops working immediately and the bytes go when the deployment
    # next reclaims storage. Unlike a rotation this needs nothing but the UUID
    # as an identifier, since nothing has to be decrypted to expire it.
    #
    # @return [Models::FileRecord] the file, with `expires_at` now in the past
    def admin_expire_file(slug, uuid)
      Models::FileRecord.from_h(@transport.post("/admin/communities/#{esc(slug)}/files/expire", { "uuid" => uuid.to_s }))
    end

    # Mark a file for deletion when its UUID is gone.
    #
    # Takes the `id` a listing gives, so this is the way to reclaim a file
    # nobody can name any more. It works because expiring decrypts nothing: the
    # expiry is a stored field, and the bytes go with the next reclaim pass.
    # Rotation has no equivalent, since rotating has to read the file and so
    # genuinely needs the UUID.
    #
    # Calling it twice is harmless. A file already expired keeps the expiry it
    # has rather than having its deletion pushed further out.
    #
    # @return [Models::FileRecord] the file, with `expires_at` now in the past
    def admin_expire_file_by_id(slug, id)
      Models::FileRecord.from_h(@transport.delete("/admin/communities/#{esc(slug)}/files/#{esc(id)}"))
    end

    # Fetch the bytes behind a download link.
    #
    # +link+ is the "url" an upload or a rotation answered with. No API key is
    # sent: the UUID inside the link is the entire credential, which is why a
    # link can be handed to anyone and why a leaked one wants
    # {#admin_rotate_file_link}.
    #
    # Given a block, each chunk is yielded as it arrives and nothing is held, so
    # a file larger than this process's memory downloads fine. Given an +io+,
    # chunks are written to it. Given neither, the whole file comes back as a
    # binary String, which is only sensible for something small.
    #
    # An expired link, a rotated-away one and one that never named anything all
    # raise {NotFound} identically.
    #
    #   File.open("out.bin", "wb") { |f| client.download_file(uploaded.url, io: f) }
    #
    # @param link [String] an absolute URL, or a path beginning with "/"
    # @param io [#write, nil]
    # @return [String, nil] the bytes, or nil when a block or an io took them
    def download_file(link, io: nil, &block)
      return @transport.download(link, &block) if block
      return @transport.download(link) { |chunk| io.write(chunk) } if io

      buffer = String.new(encoding: Encoding::BINARY)
      @transport.download(link) { |chunk| buffer << chunk }
      buffer
    end

    private

    # A path is opened in binary mode and closed again, so the common case is
    # one argument rather than a caller managing a handle around the call.
    def upload_path(slug, path, filename, content_type, room_key)
      File.open(path, "rb") do |io|
        send_upload(slug, io, filename || File.basename(path), content_type, room_key)
      end
    end

    def send_upload(slug, io, filename, content_type, room_key)
      Models::FileRecordWithLink.from_h(
        @transport.upload(
          "/admin/communities/#{esc(slug)}/files", io,
          filename: filename, content_type: content_type,
          fields: compact(room_key: room_key).transform_keys(&:to_s)
        )
      )
    end

    def esc(value) = Transport.escape_segment(value)

    # A list route's envelope. A missing key is raised on rather than treated
    # as an empty list: if the API ever renames one of these, an empty array
    # would read as "this community has none of those", which is a quieter and
    # much worse failure than an exception.
    #
    # @param query [Hash, nil] most list routes take none; the few that filter
    #   by a state pass it through here
    def list(path, key, query: nil) = unwrap(@transport.get(path, query: query), key)

    # {#list}, but mapping each row of the envelope's array into +model+
    # instead of leaving it a Hash. Every collection route in this client goes
    # through here except the handful that are genuinely arrays of strings,
    # the word filter foremost among them, which have no shape worth a class.
    def list_of(model, path, key, query: nil) = model.array(list(path, key, query: query))

    # {#list}'s envelope check, split out so a write that answers with the
    # same shape a list route does, replacing the word filter or removing a
    # FAQ entry among them, can unwrap its response the same way without a
    # second GET.
    def unwrap(body, key)
      raise MalformedResponse, "expected #{key.inspect} in the response, got #{body.keys.inspect}" unless body.key?(key)

      body.fetch(key)
    end

    # {#operators}' answer mixes two shapes the API tells apart with
    # `baked_in`: true is a handle the deployment ships with, which has no
    # grant record and so becomes {Models::BakedInOperator}; anything else is
    # a granted {Models::Operator}.
    def build_operator(row) = row["baked_in"] ? Models::BakedInOperator.from_h(row) : Models::Operator.from_h(row)

    # A PATCH body may carry `enabled`, `config`, or both. Nil means "leave
    # this alone", so neither field is defaulted to a value that would write
    # something the caller did not ask for. Both being nil is a caller
    # mistake worth raising on: the request would be legal and would change
    # nothing, which is a typo hiding as a successful call.
    def feature_body(enabled:, config:)
      raise ArgumentError, "pass enabled:, config:, or both" if enabled.nil? && config.nil?

      body = {}
      body["enabled"] = enabled unless enabled.nil?
      body["config"] = config unless config.nil?
      body
    end

    # A script write body. Nil means "leave this alone", which is what makes
    # the same builder serve both the create and the partial edit: the create
    # passes name and source so they are always present, and the edit passes
    # only what is changing.
    #
    # `condition` goes out as `trigger_type`, the name the API reads on the way
    # in. It answers with `condition`, and this keeps each name where it
    # belongs rather than picking one and quietly translating in both
    # directions.
    def script_body(name:, source:, kind:, language:, condition:, trigger_config:, yaml_data:)
      body = {}
      body["name"] = name unless name.nil?
      body["source"] = source unless source.nil?
      body["kind"] = kind unless kind.nil?
      body["language"] = language unless language.nil?
      body["trigger_type"] = condition unless condition.nil?
      body["trigger_config"] = trigger_config unless trigger_config.nil?
      body["yaml_data"] = yaml_data unless yaml_data.nil?
      body
    end

    # The same rule for an endpoint: only what was passed is sent, so an edit
    # never rewrites a field the caller did not name.
    def endpoint_body(**fields)
      fields.each_with_object({}) do |(key, value), body|
        body[key.to_s] = value unless value.nil?
      end
    end

    def compact(**params) = params.reject { |_key, value| value.nil? }
  end
end
