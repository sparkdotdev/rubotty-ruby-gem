# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One space the bot was added to, and where its review stands. It
      # belongs to no community until somebody approves it, which is why
      # `community` stays null until then.
      class PendingSpace < Base
        fields :id, :adapter, :account, :external_id, :name, :state, :inviter_username, :inviter_display,
               :can_make_operator, :member_count, :sample_channels, :community, :decided_by, :decided_at,
               :expires_at, :created_at, readonly: [:id]
      end

      # One pending space, and the community its name looks like it belongs
      # to. Nothing here writes or decides: a suggestion is accepted by
      # approving that pending space.
      class SpaceSuggestion < Base
        fields :matched, :pending_space
        cast :pending_space, ->(v) { PendingSpace.from_h(v) }
      end

      # What {Client#admin_approve_pending_space} produced: the space as it
      # now stands, and the community it landed on.
      class PendingSpaceDecision < Base
        fields :pending_space, :community
        cast :pending_space, ->(v) { PendingSpace.from_h(v) }
        cast :community, ->(v) { Community.from_h(v) }
      end
    end
  end
end
