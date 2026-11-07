# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"

# Every operation the API documents, driven once, asserting the verb and the
# path it produced, and now the shape of what came back: a model where the
# route answers with one, not a bare Hash with string keys to remember.
RSpec.describe Rubotty::Client do
  let(:client) { described_class.new(token: "k3y", base_url: "https://example.test/api") }

  # Short alias, used constantly below.
  M = Rubotty::Client::Models

  # Call, verb and path for every operation that is one request and one
  # answer. `body` is what the API would send back, so a list route's envelope
  # is present and the unwrapping runs. `model:` is what the call should hand
  # back: a class for one instance, `[SomeClass]` for an array of them, or one
  # of the symbols {#assert_shape} knows for a shape with no model of its own.
  #
  # {Client#stream_room} is the one operation missing here, since it holds a
  # connection open and yields frames rather than returning. It has its own
  # example below, and STREAMING keeps the surface count honest.
  OPERATIONS = [
    { call: [:ping], verb: "GET", path: "/api/healthz", body: "ok\n", model: :string },

    { call: [:community, "sample"], verb: "GET", path: "/api/communities/sample", model: M::Community },
    { call: [:admin_communities], verb: "GET", path: "/api/admin/communities", body: { "communities" => [] },
      model: [M::Community] },

    { call: [:rooms, "sample"], verb: "GET", path: "/api/communities/sample/rooms", body: { "rooms" => [] },
      model: [M::Room] },
    { call: [:room, "sample", "general"], verb: "GET", path: "/api/communities/sample/rooms/general", model: M::Room },
    { call: [:channels, "sample"], verb: "GET", path: "/api/communities/sample/channels", body: { "channels" => [] },
      model: [M::Channel] },
    { call: [:channel, "sample", "tg-general"], verb: "GET", path: "/api/communities/sample/channels/tg-general",
      model: M::Channel },
    { call: [:discovered_channels, "sample"], verb: "GET", path: "/api/communities/sample/discovered-channels",
      body: { "discovered_channels" => [] }, model: [M::Channel] },
    { call: [:mapping_proposals, "sample"], verb: "GET",
      path: "/api/communities/sample/discovered-channels/mapping-proposals",
      body: { "proposals" => [] }, model: [M::MappingProposal] },
    { call: [:apply_mapping_proposals, "sample", [{ "endpoint_key" => "tg-1", "room_key" => "general" }]],
      verb: "POST", path: "/api/communities/sample/discovered-channels/mapping-proposals/apply",
      body: { "applied" => 1, "requested" => 1 }, model: M::MappingApplyResult },
    { call: [:map_discovered_channel, "sample", "tg-42"], kwargs: { room_key: "general" }, verb: "POST",
      path: "/api/communities/sample/discovered-channels/tg-42/map", body: { "room" => {}, "channels" => [] },
      model: M::ChannelMapping },

    { call: [:suggested_channels, "sample"], verb: "GET", path: "/api/communities/sample/suggested-channels",
      body: { "suggested_channels" => [] }, model: [M::SuggestedChannel] },
    { call: [:approve_suggested_channel, "sample", 3], verb: "POST",
      path: "/api/communities/sample/suggested-channels/3/approve", model: M::SuggestedChannel },
    { call: [:reject_suggested_channel, "sample", 3], verb: "POST", status: 204,
      path: "/api/communities/sample/suggested-channels/3/reject", model: :true },

    { call: [:people, "sample"], verb: "GET", path: "/api/communities/sample/people", body: { "people" => [] },
      model: [M::Person] },
    { call: [:person, "sample", 12], verb: "GET", path: "/api/communities/sample/people/12", model: M::Person },
    { call: [:set_nickname, "sample", 12, "discord"], kwargs: { nickname: "Sam" }, verb: "PUT",
      path: "/api/communities/sample/people/12/nicknames/discord", model: M::Person },
    { call: [:clear_nickname, "sample", 12, "discord"], verb: "DELETE", status: 204,
      path: "/api/communities/sample/people/12/nicknames/discord", model: :true },
    { call: [:operators, "sample"], verb: "GET", path: "/api/communities/sample/operators", body: { "operators" => [] },
      model: [M::Operator] },
    { call: [:admin_grant_operator, "sample"], kwargs: { adapter: "telegram", native_id: "555" }, verb: "POST",
      status: 201, path: "/api/admin/communities/sample/operators", model: M::Operator },
    { call: [:admin_revoke_operator, "sample", 9], verb: "DELETE", status: 204,
      path: "/api/admin/communities/sample/operators/9", model: :true },
    { call: [:operator_requests, "sample"], verb: "GET", path: "/api/communities/sample/operator-requests",
      body: { "operator_requests" => [] }, model: [M::OperatorRequest] },
    { call: [:operator_request, "sample", 4], verb: "GET", path: "/api/communities/sample/operator-requests/4",
      model: M::OperatorRequest },

    { call: [:community_viewers, "sample"], verb: "GET", path: "/api/communities/sample/viewers",
      body: { "viewers" => [], "baked_in" => [] }, model: M::CommunityViewerRoster },
    { call: [:grant_community_viewer, "sample"], kwargs: { adapter: "telegram", handle: "ada" }, verb: "POST",
      status: 201, path: "/api/communities/sample/viewers", model: M::CommunityViewer },
    { call: [:revoke_community_viewer, "sample", 4], verb: "DELETE", status: 204,
      path: "/api/communities/sample/viewers/4", model: :true },
    { call: [:community_viewer_requests, "sample"], verb: "GET", path: "/api/communities/sample/viewer-requests",
      body: { "viewer_requests" => [] }, model: [M::CommunityViewerRequest] },
    { call: [:approve_community_viewer_request, "sample", 2], verb: "POST",
      path: "/api/communities/sample/viewer-requests/2/approve", body: { "request" => {}, "viewer" => {} },
      model: M::CommunityViewerRequestDecision },
    { call: [:deny_community_viewer_request, "sample", 2], verb: "POST",
      path: "/api/communities/sample/viewer-requests/2/deny", body: { "request" => {} },
      model: M::CommunityViewerRequest },
    { call: [:community_auth_tokens, "sample"], verb: "GET", path: "/api/communities/sample/auth-tokens",
      body: { "auth_tokens" => [] }, model: [M::AuthToken] },
    { call: [:mint_community_auth_token, "sample"], kwargs: { viewer: true }, verb: "POST", status: 201,
      path: "/api/communities/sample/auth-tokens", model: M::IssuedAuthToken },
    { call: [:revoke_community_auth_token, "sample", "b17c"], verb: "DELETE", status: 204,
      path: "/api/communities/sample/auth-tokens/b17c", model: :true },

    { call: [:feature_schemas], verb: "GET", path: "/api/features/schema", body: { "features" => [] },
      model: [M::FeatureSchema] },
    { call: [:community_features, "sample"], verb: "GET", path: "/api/communities/sample/features",
      body: { "features" => [] }, model: [M::Feature] },
    { call: [:community_feature, "sample", "word_filter"], verb: "GET",
      path: "/api/communities/sample/features/word_filter", model: M::Feature },
    { call: [:set_community_feature, "sample", "word_filter"], kwargs: { enabled: true }, verb: "PATCH",
      path: "/api/communities/sample/features/word_filter", model: M::Feature },
    { call: [:room_features, "sample", "general"], verb: "GET", path: "/api/communities/sample/rooms/general/features",
      body: { "features" => [] }, model: [M::Feature] },
    { call: [:room_feature, "sample", "general", "word_filter"], verb: "GET",
      path: "/api/communities/sample/rooms/general/features/word_filter", model: M::RoomFeature },
    { call: [:set_room_feature, "sample", "general", "word_filter"], kwargs: { enabled: false }, verb: "PATCH",
      path: "/api/communities/sample/rooms/general/features/word_filter", model: M::Feature },
    { call: [:reset_room_feature, "sample", "general", "word_filter"], verb: "DELETE", status: 204,
      path: "/api/communities/sample/rooms/general/features/word_filter", model: :true },

    { call: [:word_filter_entries, "sample"], verb: "GET", path: "/api/communities/sample/word-filter/entries",
      body: { "entries" => [] }, model: :array_of_strings },
    { call: [:replace_word_filter_entries, "sample", ["badword"]], verb: "PUT",
      path: "/api/communities/sample/word-filter/entries", body: { "entries" => ["badword"] },
      model: :array_of_strings },
    { call: [:remove_word_filter_entry, "sample", "badword"], verb: "DELETE",
      path: "/api/communities/sample/word-filter/entries", body: { "entries" => [] }, model: :array_of_strings },
    { call: [:room_word_filter_entries, "sample", "general"], verb: "GET",
      path: "/api/communities/sample/rooms/general/word-filter/entries", body: { "entries" => [] },
      model: :array_of_strings },
    { call: [:replace_room_word_filter_entries, "sample", "general", ["badword"]], verb: "PUT",
      path: "/api/communities/sample/rooms/general/word-filter/entries", body: { "entries" => ["badword"] },
      model: :array_of_strings },
    { call: [:remove_room_word_filter_entry, "sample", "general", "badword"], verb: "DELETE",
      path: "/api/communities/sample/rooms/general/word-filter/entries", body: { "entries" => [] },
      model: :array_of_strings },
    { call: [:faq_entries, "sample"], verb: "GET", path: "/api/communities/sample/faq/entries",
      body: { "entries" => [] }, model: [M::FaqEntry] },
    { call: [:add_faq_entry, "sample"], kwargs: { trigger: "rules", response: "be kind", trigger_type: "command" },
      verb: "POST", status: 201, path: "/api/communities/sample/faq/entries", body: { "id" => "a1b2c3d4" },
      model: M::FaqEntry },
    { call: [:remove_faq_entry, "sample", "a1b2c3d4"], verb: "DELETE", path: "/api/communities/sample/faq/entries/a1b2c3d4",
      body: { "entries" => [] }, model: [M::FaqEntry] },
    { call: [:room_faq_entries, "sample", "general"], verb: "GET",
      path: "/api/communities/sample/rooms/general/faq/entries", body: { "entries" => [] }, model: [M::FaqEntry] },
    { call: [:add_room_faq_entry, "sample", "general"],
      kwargs: { trigger: "rules", response: "be kind", trigger_type: "command" }, verb: "POST", status: 201,
      path: "/api/communities/sample/rooms/general/faq/entries", body: { "id" => "a1b2c3d4" }, model: M::FaqEntry },
    { call: [:remove_room_faq_entry, "sample", "general", "a1b2c3d4"], verb: "DELETE",
      path: "/api/communities/sample/rooms/general/faq/entries/a1b2c3d4", body: { "entries" => [] },
      model: [M::FaqEntry] },
    { call: [:join_links, "sample"], verb: "GET", path: "/api/communities/sample/join-links",
      body: { "join_links" => [] }, model: [M::JoinLink] },
    { call: [:replace_join_links, "sample", [{ "url" => "https://discord.gg/x" }]], verb: "PUT",
      path: "/api/communities/sample/join-links", body: { "join_links" => [] }, model: [M::JoinLink] },
    { call: [:room_join_links, "sample", "general"], verb: "GET",
      path: "/api/communities/sample/rooms/general/join-links", body: { "join_links" => [] }, model: [M::JoinLink] },
    { call: [:replace_room_join_links, "sample", "general", [{ "url" => "https://discord.gg/x" }]], verb: "PUT",
      path: "/api/communities/sample/rooms/general/join-links", body: { "join_links" => [] }, model: [M::JoinLink] },

    { call: [:platform_connections, "sample"], verb: "GET", path: "/api/communities/sample/platform-connections",
      body: { "platform_connections" => [] }, model: [M::PlatformConnection] },
    { call: [:irc_networks, "sample"], verb: "GET", path: "/api/communities/sample/irc-networks",
      body: { "irc_networks" => [] }, model: [M::IrcNetwork] },
    { call: [:irc_network, "sample", "libera"], verb: "GET", path: "/api/communities/sample/irc-networks/libera",
      model: M::IrcNetwork },
    { call: [:fluxer_instances, "sample"], verb: "GET", path: "/api/communities/sample/fluxer-instances",
      body: { "fluxer_instances" => [] }, model: [M::FluxerInstance] },
    { call: [:fluxer_instance, "sample", "flagship"], verb: "GET",
      path: "/api/communities/sample/fluxer-instances/flagship", model: M::FluxerInstance },

    { call: [:guest_invites, "sample"], verb: "GET", path: "/api/communities/sample/guest-invites",
      body: { "guest_invites" => [] }, model: [M::GuestInvite] },
    { call: [:guest_invite, "sample", 7], verb: "GET", path: "/api/communities/sample/guest-invites/7",
      model: M::GuestInvite },
    { call: [:room_events, "sample", "general"], verb: "GET", path: "/api/communities/sample/rooms/general/events",
      body: { "events" => [] }, model: [M::Event] },
    { call: [:event, "sample", 3], verb: "GET", path: "/api/communities/sample/events/3", model: M::Event },

    { call: [:admin_pending_spaces], verb: "GET", path: "/api/admin/pending-spaces",
      body: { "pending_spaces" => [] }, model: [M::PendingSpace] },
    { call: [:admin_pending_space, 8], verb: "GET", path: "/api/admin/pending-spaces/8", model: M::PendingSpace },
    { call: [:admin_clear_pending_space, 8], verb: "DELETE", status: 204, path: "/api/admin/pending-spaces/8",
      model: :true },
    { call: [:admin_approve_pending_space, 8], kwargs: { community: "sample" }, verb: "POST",
      path: "/api/admin/pending-spaces/8/approve", body: { "pending_space" => {}, "community" => {} },
      model: M::PendingSpaceDecision },
    { call: [:admin_reject_pending_space, 8], verb: "POST", path: "/api/admin/pending-spaces/8/reject",
      model: M::PendingSpace },
    { call: [:admin_space_suggestions, "sample"], verb: "GET", path: "/api/admin/communities/sample/space-suggestions",
      body: { "suggestions" => [] }, model: [M::SpaceSuggestion] },

    { call: [:room_participation, "sample", "general"], verb: "GET",
      path: "/api/communities/sample/rooms/general/participation", body: { "session" => nil, "standings" => [] },
      model: M::RoomParticipation },
    { call: [:close_room_participation, "sample", "general"], verb: "POST",
      path: "/api/communities/sample/rooms/general/participation/close", body: { "closed" => true }, model: :true },

    { call: [:admin_accounts], verb: "GET", path: "/api/admin/accounts", body: { "accounts" => [] },
      model: [M::Account] },
    { call: [:admin_account, "telegram", "telegram"], verb: "GET", path: "/api/admin/accounts/telegram/telegram",
      model: M::Account },
    { call: [:admin_api_keys], verb: "GET", path: "/api/admin/api-keys", body: { "api_keys" => [] },
      model: [M::ApiKey] },
    { call: [:admin_integrations], verb: "GET", path: "/api/admin/integrations", body: { "integrations" => [] },
      model: [M::Integration] },
    { call: [:admin_integration, "libretranslate"], verb: "GET", path: "/api/admin/integrations/libretranslate",
      model: M::Integration },

    { call: [:admin_viewers], verb: "GET", path: "/api/admin/viewers", body: { "viewers" => [], "baked_in" => [] },
      model: M::ViewerRoster },
    { call: [:admin_grant_viewer], kwargs: { adapter: "telegram", handle: "ada" }, verb: "POST", status: 201,
      path: "/api/admin/viewers", model: M::Viewer },
    { call: [:admin_revoke_viewer, 6], verb: "DELETE", status: 204, path: "/api/admin/viewers/6", model: :true },
    { call: [:admin_viewer_requests], verb: "GET", path: "/api/admin/viewer-requests",
      body: { "viewer_requests" => [] }, model: [M::ViewerRequest] },
    { call: [:admin_approve_viewer_request, 3], verb: "POST", path: "/api/admin/viewer-requests/3/approve",
      body: { "request" => {}, "viewer" => {} }, model: M::ViewerRequestDecision },
    { call: [:admin_deny_viewer_request, 3], verb: "POST", path: "/api/admin/viewer-requests/3/deny",
      body: { "request" => {} }, model: M::ViewerRequest },

    { call: [:admin_auth_tokens], verb: "GET", path: "/api/admin/auth-tokens", body: { "auth_tokens" => [] },
      model: [M::AuthToken] },
    { call: [:admin_mint_auth_token], kwargs: { ttl_seconds: 3600 }, verb: "POST", status: 201,
      path: "/api/admin/auth-tokens", model: M::IssuedAuthToken },
    { call: [:admin_revoke_auth_token, "b17c"], verb: "DELETE", status: 204, path: "/api/admin/auth-tokens/b17c",
      model: :true },

    { call: [:admin_community_stats, "sample"], verb: "GET", path: "/api/admin/communities/sample/stats",
      model: M::Stats },
    { call: [:admin_debug_info], verb: "GET", path: "/api/admin/debug/info", model: M::DebugInfo },
    { call: [:admin_debug_logs], verb: "GET", path: "/api/admin/debug/logs", body: { "entries" => [] },
      model: M::DebugLog },
    { call: [:admin_debug_backfill_gaps], verb: "GET", path: "/api/admin/debug/backfill-gaps",
      body: { "channels" => [] }, model: M::BackfillGapsReport },

    { call: [:post_message, "sample", "general", "hello"], verb: "POST", status: 201,
      path: "/api/communities/sample/rooms/general/messages",
      body: { "status" => "queued", "id" => 1, "room_key" => "general" }, model: M::MessageQueued },
    { call: [:edit_message, "sample", "general", "1", "edited"], verb: "PATCH", status: 202,
      path: "/api/communities/sample/rooms/general/messages/1", body: { "status" => "queued" },
      model: M::QueuedStatus },
    { call: [:delete_message, "sample", "general", "1"], verb: "DELETE", status: 202,
      path: "/api/communities/sample/rooms/general/messages/1", body: { "status" => "queued" },
      model: M::QueuedStatus },
    { call: [:add_reaction, "sample", "general", "1", { "emoji" => "👍" }], verb: "PUT", status: 202,
      path: "/api/communities/sample/rooms/general/messages/1/reactions", body: { "status" => "queued" },
      model: M::QueuedStatus },
    { call: [:remove_reaction, "sample", "general", "1", { "emoji" => "👍" }], verb: "DELETE", status: 202,
      path: "/api/communities/sample/rooms/general/messages/1/reactions", body: { "status" => "queued" },
      model: M::QueuedStatus },

    { call: [:post_bridge_message, "sample", "support-42"], kwargs: { body: "hello" }, verb: "POST", status: 201,
      path: "/api/communities/sample/bridge/channels/support-42/messages",
      body: { "status" => "queued", "message_id" => "1" }, model: M::BridgeMessageQueued },
    { call: [:edit_bridge_message, "sample", "support-42", "1"], kwargs: { body: "edited" }, verb: "PATCH",
      status: 202, path: "/api/communities/sample/bridge/channels/support-42/messages/1",
      body: { "status" => "queued" }, model: M::QueuedStatus },
    { call: [:delete_bridge_message, "sample", "support-42", "1"], verb: "DELETE", status: 202,
      path: "/api/communities/sample/bridge/channels/support-42/messages/1", body: { "status" => "queued" },
      model: M::QueuedStatus },
    { call: [:add_bridge_reaction, "sample", "support-42", "1"], kwargs: { reaction: { "emoji" => "👍" } },
      verb: "PUT", status: 202, path: "/api/communities/sample/bridge/channels/support-42/messages/1/reactions",
      body: { "status" => "queued" }, model: M::QueuedStatus },
    { call: [:remove_bridge_reaction, "sample", "support-42", "1"], kwargs: { reaction: { "emoji" => "👍" } },
      verb: "DELETE", status: 202, path: "/api/communities/sample/bridge/channels/support-42/messages/1/reactions",
      body: { "status" => "queued" }, model: M::QueuedStatus },

    { call: [:admin_scripts, "sample"], verb: "GET", path: "/api/admin/communities/sample/scripts",
      body: { "scripts" => [] }, model: [M::Script] },
    { call: [:admin_archived_scripts, "sample"], verb: "GET", path: "/api/admin/communities/sample/scripts/archived",
      body: { "scripts" => [] }, model: [M::Script] },
    { call: [:admin_script, "sample", 5], verb: "GET", path: "/api/admin/communities/sample/scripts/5",
      model: M::Script },
    { call: [:admin_create_script, "sample"], kwargs: { name: "guard", source: "return 1" }, verb: "POST",
      status: 201, path: "/api/admin/communities/sample/scripts", model: M::Script },
    { call: [:admin_update_script, "sample", 5], kwargs: { name: "guard renamed" }, verb: "PATCH",
      path: "/api/admin/communities/sample/scripts/5", model: M::Script },
    { call: [:admin_archive_script, "sample", 5], verb: "DELETE", status: 204,
      path: "/api/admin/communities/sample/scripts/5", model: :true },
    { call: [:admin_restore_script, "sample", 5], verb: "POST",
      path: "/api/admin/communities/sample/scripts/5/restore", model: M::Script },
    { call: [:admin_verify_script, "sample", 5], verb: "POST",
      path: "/api/admin/communities/sample/scripts/5/verify", body: { "ok" => true, "problems" => [] },
      model: M::ScriptVerification },
    { call: [:admin_enable_script, "sample", 5], verb: "POST",
      path: "/api/admin/communities/sample/scripts/5/enable", model: M::Script },
    { call: [:admin_disable_script, "sample", 5], verb: "POST",
      path: "/api/admin/communities/sample/scripts/5/disable", model: M::Script },
    { call: [:admin_scripting_capabilities], verb: "GET", path: "/api/admin/scripting/capabilities",
      model: M::ScriptingCapabilities },

    { call: [:admin_script_endpoints, "sample"], verb: "GET", path: "/api/admin/communities/sample/endpoints",
      body: { "endpoints" => [] }, model: [M::ScriptEndpoint] },
    { call: [:admin_script_endpoint, "sample", 2], verb: "GET", path: "/api/admin/communities/sample/endpoints/2",
      model: M::ScriptEndpoint },
    { call: [:admin_create_script_endpoint, "sample"],
      kwargs: { name: "weather", url: "https://example.test/now" }, verb: "POST", status: 201,
      path: "/api/admin/communities/sample/endpoints", model: M::ScriptEndpoint },
    { call: [:admin_update_script_endpoint, "sample", 2], kwargs: { cache_seconds: 60 }, verb: "PATCH",
      path: "/api/admin/communities/sample/endpoints/2", model: M::ScriptEndpoint },
    { call: [:admin_delete_script_endpoint, "sample", 2], verb: "DELETE", status: 204,
      path: "/api/admin/communities/sample/endpoints/2", model: :true },

    { call: [:admin_script_errors, "sample", 5], verb: "GET",
      path: "/api/admin/communities/sample/scripts/5/errors",
      body: { "id" => 5, "name" => "guard", "consecutive_failures" => 0, "errors" => [] },
      model: M::ScriptErrors },

    { call: [:admin_script_stats, "sample"], verb: "GET", path: "/api/admin/communities/sample/script-stats",
      body: { "stats" => {} }, model: :hash_of_stat_rows },

    { call: [:alerts, "sample"], verb: "GET", path: "/api/communities/sample/alerts",
      body: { "alerts" => [], "unseen" => 0 }, model: M::AlertList },
    { call: [:mark_alert_seen, "sample", 3], verb: "POST", path: "/api/communities/sample/alerts/3/seen",
      model: M::Alert },
    { call: [:mark_all_alerts_seen, "sample"], verb: "POST", path: "/api/communities/sample/alerts/seen",
      body: { "marked" => 0 }, model: :integer },

    { call: [:admin_webhooks, "sample"], verb: "GET", path: "/api/admin/communities/sample/webhooks",
      body: { "webhooks" => [] }, model: [M::Webhook] },
    { call: [:admin_webhook, "sample", "b17c"], verb: "GET", path: "/api/admin/communities/sample/webhooks/b17c",
      model: M::Webhook },
    { call: [:admin_create_webhook, "sample"],
      kwargs: { url: "https://example.test/hook", event_types: "message.relayed" },
      verb: "POST", status: 201, path: "/api/admin/communities/sample/webhooks", model: M::WebhookWithSecret },
    { call: [:admin_rotate_webhook_secret, "sample", "b17c"], verb: "POST",
      path: "/api/admin/communities/sample/webhooks/b17c/rotate", model: M::WebhookWithSecret },
    { call: [:admin_delete_webhook, "sample", "b17c"], verb: "DELETE", status: 204,
      path: "/api/admin/communities/sample/webhooks/b17c", model: :true },
    { call: [:admin_webhook_deliveries, "sample"], verb: "GET",
      path: "/api/admin/communities/sample/webhook-deliveries", body: { "deliveries" => [] },
      model: [M::WebhookDelivery] },

    { call: [:admin_backfill_proposals], verb: "GET", path: "/api/admin/backfill-proposals",
      body: { "backfill_proposals" => [] }, model: [M::BackfillProposal] },
    { call: [:admin_backfill_proposal, 9], verb: "GET", path: "/api/admin/backfill-proposals/9",
      model: M::BackfillProposalDetail },
    { call: [:admin_approve_backfill_proposal, 9], verb: "POST", path: "/api/admin/backfill-proposals/9/approve",
      body: { "backfill_proposal" => {}, "item_count" => 0, "relaying" => true },
      model: M::BackfillProposalApproval },
    { call: [:admin_reject_backfill_proposal, 9], verb: "POST", path: "/api/admin/backfill-proposals/9/reject",
      body: { "backfill_proposal" => {} }, model: M::BackfillProposal },

    { call: [:admin_files, "sample"], verb: "GET", path: "/api/admin/communities/sample/files",
      body: { "files" => [] }, model: [M::FileRecord] },
    { call: [:admin_file, "sample", 9], verb: "GET", path: "/api/admin/communities/sample/files/9",
      model: M::FileRecord },
    { call: [:admin_upload_file, "sample", StringIO.new("some bytes")], kwargs: { filename: "clip.mp4" },
      verb: "POST", status: 201, path: "/api/admin/communities/sample/files", model: M::FileRecordWithLink },
    { call: [:admin_rotate_file_link, "sample", "the-uuid"], verb: "POST",
      path: "/api/admin/communities/sample/files/rotate", model: M::FileRecordWithLink },
    { call: [:admin_expire_file, "sample", "the-uuid"], verb: "POST",
      path: "/api/admin/communities/sample/files/expire", model: M::FileRecord },
    { call: [:admin_expire_file_by_id, "sample", 9], verb: "DELETE",
      path: "/api/admin/communities/sample/files/9", model: M::FileRecord }
  ].freeze

  # Driven separately, not absent. Listed so the surface check below still
  # accounts for every public method.
  STREAMING = %i[stream_room].freeze

  # Public, and not an API route, so it is held apart from the count below.
  # A download link is served at the web surface's own root rather than under
  # the API mount, and it carries no key: the UUID in the link is the whole
  # credential, so the request sends no Authorization header at all.
  NON_API = %i[download_file].freeze

  # What `model:` on an {OPERATIONS} row means, checked against whatever the
  # call actually returned. A Class means one instance of it; a one-element
  # Array names the element type of an Array result; the symbols cover every
  # shape this client hands back with no model of its own, either because the
  # API answers a bare scalar (`:integer`) or because the field is genuinely
  # free-form text with no shape to model (`:array_of_strings`).
  def assert_shape(result, shape)
    case shape
    when :true then expect(result).to be(true)
    when :string then expect(result).to be_a(String)
    when :integer then expect(result).to be_an(Integer)
    when :array_of_strings
      expect(result).to be_an(Array)
      expect(result).to all(be_a(String))
    when :hash_of_stat_rows
      expect(result).to be_a(Hash)
      result.each_value { |rows| expect(rows).to all(be_a(M::ScriptStatRow)) }
    when Array
      expect(result).to be_an(Array)
      expect(result).to all(be_a(shape.first))
    else
      expect(result).to be_a(shape)
    end
  end

  it "sends each operation to the route the API spec documents, and builds the model its doc comment promises" do
    OPERATIONS.each do |row|
      name, *args = row[:call]
      body = row.fetch(:body, {})
      stub_http(status: row.fetch(:status, 200), body: body.is_a?(String) ? body : YAMLCamel.dump(body))

      result = client.public_send(name, *args, **row.fetch(:kwargs, {}))

      expect([name, last_request.method, last_request.path]).to eq([name, row[:verb], row[:path]])
      assert_shape(result, row[:model]) if row[:model]
    end
  end

  it "has one method per operation and nothing else on its public surface" do
    covered = OPERATIONS.map { |row| row[:call].first } + STREAMING
    surface = described_class.public_instance_methods(false) - %i[transport base_url]

    expect((covered + NON_API).sort).to eq(surface.sort)
    # One per route the API serves. The count is asserted rather than left
    # implicit, because the surface check above only proves the two lists in
    # this file agree with each other, which they would go on doing while the
    # API grew routes neither of them knows about.
    expect(covered.size).to eq(139)
  end

  describe "what each family gives back" do
    it "unwraps a list route's envelope and returns an Array of the model, not of Hashes" do
      stub_http(body: YAMLCamel.dump({ "rooms" => [{ "room_key" => "general", "label" => "General",
                                                "channels" => %w[tg-general dc-general] }] }))

      rooms = client.rooms("sample")

      expect(rooms).to all(be_a(M::Room))
      expect([rooms.first.room_key, rooms.first.label, rooms.first.channels])
        .to eq(["general", "General", %w[tg-general dc-general]])
    end

    it "returns a single resource as the model it arrived as, with working accessors" do
      stub_http(body: YAMLCamel.dump({ "id" => 7, "nickname" => "visitor", "room_key" => "general",
                                  "expires_at" => "2026-08-01 12:00:00 +0100" }))

      invite = client.guest_invite("sample", 7)

      expect(invite).to be_a(M::GuestInvite)
      expect([invite.nickname, invite.expires_at]).to eq(["visitor", "2026-08-01 12:00:00 +0100"])
    end

    it "gives the word filter back as plain strings, since an entry has no shape beyond its text" do
      stub_http(body: YAMLCamel.dump({ "entries" => ["badword", "a rude phrase"] }))

      expect(client.room_word_filter_entries("sample", "general")).to eq(["badword", "a rude phrase"])
    end

    it "returns the row a feature write produced as a Feature, so no read-back call is needed" do
      stub_http(body: YAMLCamel.dump({ "scope" => "room", "room_key" => "general", "feature" => "word_filter",
                                  "enabled" => true, "config" => { "action" => "delete" } }))

      result = client.set_room_feature("sample", "general", "word_filter", enabled: true, config: { "action" => "delete" })

      expect(result).to be_a(M::Feature)
      expect([result.enabled, result.config]).to eq([true, { "action" => "delete" }])
    end

    # Kept whole rather than unwrapped to "entries": a caller that never sees
    # "errors" would read a half-answer (one process unreachable) as a
    # complete one, which is the trap the endpoint exists to close.
    it "keeps the debug log envelope, errors included, as a DebugLog" do
      stub_http(body: YAMLCamel.dump({ "entries" => [{ "source" => "web", "time" => "2026-07-26T09:00:00Z",
                                                  "level" => "warn", "text" => "slow query" }],
                                  "errors" => { "bot" => "could not reach the bot process" } }))

      logs = client.admin_debug_logs(source: "all")

      expect(logs).to be_a(M::DebugLog)
      expect(logs.entries).to all(be_a(M::LogEntry))
      expect([logs.entries.first.source, logs.entries.first.text]).to eq(["web", "slow query"])
      expect(logs.errors).to eq("bot" => "could not reach the bot process")
    end

    it "returns the analytics overview as a Stats, its named fields real accessors and the rest under sections" do
      stub_http(body: YAMLCamel.dump({ "window" => "7d", "moderation" => { "actions" => 3 },
                                  "members" => { "active" => 42 } }))

      stats = client.admin_community_stats("sample")

      expect(stats).to be_a(M::Stats)
      expect(stats.window).to eq("7d")
      expect(stats.sections).to eq("moderation" => { "actions" => 3 }, "members" => { "active" => 42 })
    end

    it "unwraps the script stats envelope, typing each counter's rows without flattening the counter names" do
      stub_http(body: YAMLCamel.dump({ "stats" => { "greeted" => [{ "row" => "ada", "value" => 12,
                                                               "room_key" => "general" }] } }))

      stats = client.admin_script_stats("sample")

      expect(stats.keys).to eq(["greeted"])
      expect(stats["greeted"]).to all(be_a(M::ScriptStatRow))
      expect([stats["greeted"].first.row, stats["greeted"].first.value]).to eq(["ada", 12])
    end

    it "sends a script's condition as trigger_type, the name the API reads" do
      stub_http(status: 201, body: YAMLCamel.dump({ "id" => 5, "condition" => "command" }))

      client.admin_create_script("sample", name: "greet", source: "return 1",
                                 kind: "command", condition: "command",
                                 trigger_config: { "name" => "hello" })

      # Nested, so it goes out as YAML rather than form-encoded.
      body = YAMLCamel.load(last_request.body)
      expect(body).to include("trigger_type" => "command", "kind" => "command")
      expect(body).not_to have_key("condition")
    end

    it "sends only the fields an edit named, so the rest keep their values" do
      stub_http(body: YAMLCamel.dump({ "id" => 2 }))

      client.admin_update_script_endpoint("sample", 2, cache_seconds: 60)

      expect(URI.decode_www_form(last_request.body).to_h).to eq("cache_seconds" => "60")
    end

    it "refuses an edit that would name nothing to change" do
      expect { client.admin_update_script("sample", 5) }.to raise_error(ArgumentError, /at least one field/)
      expect { client.admin_update_script_endpoint("sample", 2) }.to raise_error(ArgumentError, /at least one field/)
    end

    # Kept whole rather than unwrapped to "alerts", for the same reason the
    # debug log envelope is: the count comes back with the list and counts
    # everything outstanding rather than everything on this page.
    it "keeps the alerts envelope, unseen count included, as an AlertList" do
      stub_http(body: YAMLCamel.dump({ "alerts" => [{ "id" => 4, "text" => "airdrop links again",
                                                 "mode" => "loud", "seen_at" => nil }],
                                  "unseen" => 7 }))

      answer = client.alerts("sample")

      expect(answer).to be_a(M::AlertList)
      expect(answer.alerts).to all(be_a(M::Alert))
      expect(answer.alerts.first.text).to eq("airdrop links again")
      expect(answer.unseen).to eq(7)
    end

    it "passes an alert limit through as a query" do
      stub_http(body: YAMLCamel.dump({ "alerts" => [], "unseen" => 0 }))

      client.alerts("sample", limit: 20)

      expect(last_request.path).to eq("/api/communities/sample/alerts?limit=20")
    end

    # A DELETE with a body is the odd one out: every other DELETE in this
    # client addresses its target by path alone. Worth proving the value
    # actually rides the request rather than being dropped on the floor.
    it "sends a word filter removal's value in the DELETE body, and returns the survivors as plain strings" do
      stub_http(body: YAMLCamel.dump({ "entries" => ["a rude phrase"] }))

      result = client.remove_word_filter_entry("sample", "badword")

      expect(URI.decode_www_form(last_request.body).to_h).to eq("value" => "badword")
      expect(result).to eq(["a rude phrase"])
    end

    # Removing a FAQ entry answers with the survivors rather than a bare
    # true, unlike almost every other DELETE here: there is no second call
    # needed to see what is left of a small hand-managed list.
    it "returns the survivors from a FAQ removal as Array<FaqEntry> rather than a bare true" do
      stub_http(body: YAMLCamel.dump({ "entries" => [{ "id" => "z9y8", "command" => "faq" }] }))

      result = client.remove_faq_entry("sample", "a1b2c3d4")

      expect(result).to all(be_a(M::FaqEntry))
      expect([result.first.id, result.first.command]).to eq(["z9y8", "faq"])
    end

    it "sends a bridge reaction's author and reaction as nested YAML" do
      stub_http(status: 202, body: YAMLCamel.dump({ "status" => "queued" }))

      client.add_bridge_reaction("sample", "support-42", "1", reaction: { "emoji" => "👍" },
                                                            author: { "id" => "42", "name" => "Ada" })

      expect(last_request["Content-Type"]).to eq("application/yaml")
      body = YAMLCamel.load(last_request.body)
      expect(body).to eq("reaction" => { "emoji" => "👍" }, "author" => { "id" => "42", "name" => "Ada" })
    end

    it "leaves an unset bridge message author out of the body rather than sending it nil" do
      stub_http(status: 201, body: YAMLCamel.dump({ "status" => "queued", "message_id" => "1" }))

      client.post_bridge_message("sample", "support-42", body: "hello")

      expect(URI.decode_www_form(last_request.body).to_h).to eq("body" => "hello")
    end

    # {Client#operators} mixes two shapes the API tells apart with
    # `baked_in`, and the table above only ever stubs it empty, so the
    # dispatch between the two model classes gets its own example here.
    it "sorts a granted operator into Operator and a shipped owner into BakedInOperator" do
      stub_http(body: YAMLCamel.dump({ "operators" => [
                     { "id" => 1, "person" => "Ada", "actions" => "all", "scope" => "all", "baked_in" => false,
                       "removable" => true },
                     { "handle" => "root", "kind" => "username", "actions" => "all", "scope" => "all",
                       "baked_in" => true, "removable" => false }
                   ] }))

      granted, shipped = client.operators("sample")

      expect(granted).to be_a(M::Operator)
      expect(granted.person).to eq("Ada")
      expect(shipped).to be_a(M::BakedInOperator)
      expect(shipped.handle).to eq("root")
    end

    # {Models::ScriptingCapabilities} is one of the deepest nestings in this
    # client: an array of one model, an array of another, and a third nested
    # single object, all under one response.
    it "nests ScriptingCapabilities' kinds, conditions and limits as their own models" do
      stub_http(body: YAMLCamel.dump({ "kinds" => [{ "kind" => "processor", "label" => "Runs on every message" }],
                    "conditions" => [{ "condition" => "always", "summary" => "Every message", "fields" => [],
                                       "hands_over" => %w[author message] }],
                    "languages" => %w[lua moonscript],
                    "limits" => { "scripts_per_community" => 50, "host_calls_per_invocation" => 20,
                                  "yaml_data_bytes" => 4096 } }))

      caps = client.admin_scripting_capabilities

      expect(caps.kinds.first).to be_a(M::ScriptKind)
      expect(caps.conditions.first).to be_a(M::ScriptCondition)
      expect(caps.limits).to be_a(M::ScriptingLimits)
      expect([caps.kinds.first.kind, caps.limits.scripts_per_community]).to eq(["processor", 50])
    end
  end

  # The one operation that holds a connection open. What is worth proving is
  # the frame reassembly (SSE frames arrive split across chunk boundaries in
  # practice, and a client that treated a chunk as a frame would drop
  # messages under exactly the load a live feed is for) and the shape the
  # maintainer actually asked for: `frame.cursor`, not `frame["cursor"]`.
  describe "stream_room" do
    let(:opening) { "id: 0\ndata: ---\ndata: room_key: general\ndata: cursor: 0\ndata: messages: []\n\n" }
    let(:message) do
      "id: 7\ndata: ---\ndata: room_key: general\ndata: cursor: 7\ndata: messages:\n" \
        "data: - id: 7\ndata:   origin: tg-general\ndata:   author: ada\ndata:   body: hello\n" \
        "data:   kind: chat\ndata:   at: '2026-07-29 16:00:00 +0100'\n\n"
    end

    it "yields each frame as a StreamFrame, reassembled across chunk boundaries" do
      # Deliberately cut mid-frame, and with a heartbeat in between.
      stub_sse([opening[0, 20], opening[20..], ": heartbeat\n\n", message[0, 40], message[40..]])
      seen = []

      client.stream_room("sample", "general") { |frame| seen << frame }

      expect(seen.length).to eq(2)
      expect(seen).to all(be_a(M::StreamFrame))
      expect([seen.first.room_key, seen.first.cursor, seen.first.messages]).to eq(["general", 0, []])
      expect(seen.last.cursor).to eq(7)
      expect(seen.last.messages.first).to be_a(M::StreamMessage)
      expect([seen.last.messages.first.author, seen.last.messages.first.body]).to eq(%w[ada hello])
    end

    # Typed stream access: no bracket or string-key
    # access anywhere in a realistic usage example.
    it "reads like frame.cursor and m.author, with no hash-style access anywhere" do
      stub_sse([opening, message])
      lines = []

      client.stream_room("sample", "general") do |frame|
        frame.messages.each { |m| lines << "#{m.author}: #{m.body}" }
        raise StopIteration if frame.cursor == 7
      end

      expect(lines).to eq(["ada: hello"])
    end

    it "asks for an event stream and passes since through as a query" do
      stub_sse([opening])

      client.stream_room("sample", "general", since: 42) { |_frame| raise StopIteration }

      expect(last_request.path).to eq("/api/communities/sample/rooms/general/stream?since=42")
      expect(last_request["Accept"]).to eq("text/event-stream")
    end

    it "closes cleanly when the block raises StopIteration" do
      stub_sse([opening, message])
      seen = []

      client.stream_room("sample", "general") do |frame|
        seen << frame
        raise StopIteration
      end

      expect(seen.length).to eq(1)
    end

    it "raises the ordinary error class when the stream is refused" do
      stub_sse([YAMLCamel.dump({ "error" => "not found" })], status: 404)

      expect { client.stream_room("sample", "nope") { |_| nil } }
        .to raise_error(Rubotty::Client::NotFound, "not found")
    end

    it "insists on a block, since there is nothing to return without one" do
      expect { client.stream_room("sample", "general") }.to raise_error(ArgumentError, /needs a block/)
    end
  end

  describe "downloading a file" do
    let(:link) { "https://files.example/f/2f1c8a44-0000-4000-8000-000000000001" }

    # The property worth guarding hardest. A download link is a capability, and
    # the route serving it never reads an Authorization header, so sending the
    # API key would put it on a request at whatever host the link names.
    it "sends no bearer token" do
      stub_sse(["bytes"])

      client.download_file(link) { |_| nil }

      expect(last_request["Authorization"]).to be_nil
      expect(last_request["User-Agent"]).to include("rubotty-client")
    end

    it "goes to the host the link names, not the API's" do
      stub_sse(["bytes"])

      client.download_file(link) { |_| nil }

      expect(last_connection[:host]).to eq("files.example")
      expect(last_request.path).to eq("/f/2f1c8a44-0000-4000-8000-000000000001")
    end

    # A deployment with no public base URL configured answers with a bare path.
    # The API mount must not be prepended: the download route sits at the web
    # surface's root, alongside /api rather than under it.
    it "resolves a bare path against its own origin, without the API mount" do
      stub_sse(["bytes"])

      client.download_file("/f/the-uuid") { |_| nil }

      expect(last_connection[:host]).to eq("example.test")
      expect(last_request.path).to eq("/f/the-uuid")
    end

    it "yields each chunk as it arrives rather than holding the file" do
      stub_sse(%w[one two three])
      seen = []

      result = client.download_file(link) { |chunk| seen << chunk }

      expect(seen).to eq(%w[one two three])
      expect(result).to be_nil
    end

    it "writes to an io when given one" do
      stub_sse(%w[one two])
      sink = StringIO.new

      client.download_file(link, io: sink)

      expect(sink.string).to eq("onetwo")
    end

    it "returns the whole thing when given neither" do
      stub_sse(%w[one two])

      expect(client.download_file(link)).to eq("onetwo")
    end

    it "raises before yielding anything, so an error page is never written out" do
      stub_sse([YAMLCamel.dump({ "error" => "not found" })], status: 404)
      seen = []

      expect { client.download_file(link) { |chunk| seen << chunk } }
        .to raise_error(Rubotty::Client::NotFound)
      expect(seen).to be_empty
    end

    it "refuses a link that is neither a URL nor a path" do
      expect { client.download_file("f/the-uuid") }.to raise_error(ArgumentError, /http URL or a path/)
      expect { client.download_file("") }.to raise_error(ArgumentError, /no download link/)
    end
  end

  # The one request in this API that is neither form-encoded nor YAML.
  describe "uploading a file" do
    let(:created) { YAMLCamel.dump({ "id" => 9, "filename" => "clip.mp4", "uuid" => "u-u-i-d" }) }

    it "sends it as multipart rather than as a body this API would otherwise take" do
      stub_http(status: 201, body: created)

      client.admin_upload_file("sample", StringIO.new("bytes"), filename: "clip.mp4", content_type: "video/mp4")

      expect(last_request.content_type).to eq("multipart/form-data")
      expect(last_request["Authorization"]).to eq("Bearer k3y")
    end

    it "returns a FileRecordWithLink built from what the upload answered" do
      stub_http(status: 201, body: created)

      result = client.admin_upload_file("sample", StringIO.new("bytes"), filename: "clip.mp4")

      expect(result).to be_a(M::FileRecordWithLink)
      expect([result.filename, result.uuid]).to eq(["clip.mp4", "u-u-i-d"])
    end

    # An upload takes as long as the file and the link make it take, and the
    # far end seals the whole thing before answering, so a timeout that suits
    # an ordinary request would tear down a transfer that was working.
    it "lifts the read and write timeouts, keeping the connect timeout" do
      stub_http(status: 201, body: created)

      client.admin_upload_file("sample", StringIO.new("bytes"), filename: "clip.mp4")

      expect(last_connection).to include(open_timeout: 5, read_timeout: nil, write_timeout: nil)
    end

    it "opens a path and names the part after it" do
      allow(client.transport).to receive(:upload).and_return({})

      Tempfile.create(["clip", ".mp4"]) do |file|
        client.admin_upload_file("sample", file.path)

        expect(client.transport).to have_received(:upload)
          .with("/admin/communities/sample/files", anything,
                hash_including(filename: File.basename(file.path)))
      end
    end

    it "insists on a filename for an IO with no path of its own" do
      expect { client.admin_upload_file("sample", StringIO.new("bytes")) }
        .to raise_error(ArgumentError, /filename/)
    end

    it "refuses something that is neither a path nor readable" do
      expect { client.admin_upload_file("sample", 42) }
        .to raise_error(ArgumentError, /path or an object/)
    end
  end
end
