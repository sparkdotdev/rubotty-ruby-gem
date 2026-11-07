# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One candidate {Client#admin_debug_backfill_gaps} classified as a
      # gap. No message body, only enough to find it again.
      class BackfillGapFinding < Base
        fields :endpoint_id, :native_id, :timestamp
      end

      # One swept channel's tally from {Client#admin_debug_backfill_gaps},
      # worst (most gaps) first. Never carries a message body.
      class BackfillGapChannel < Base
        fields :endpoint_id, :community, :since, :fetched, :gaps, :ours, :claimed, :below_floor, :samples, :error
        cast :samples, ->(v) { BackfillGapFinding.array(v) }
      end

      # {Client#admin_debug_backfill_gaps}'s answer. `errors` stays a plain
      # Hash, present only when the bot process could not be reached.
      class BackfillGapsReport < Base
        fields :channels, :errors
        cast :channels, ->(v) { BackfillGapChannel.array(v) }
      end

      # One channel's held-back list and where its decision stands. The
      # counts are what the sweep itself saw, not a recount taken later,
      # which is what makes them safe to judge by. `ours` is the one to read
      # first: how many of the fetched messages the sweep recognised as this
      # bridge's own relayed copies and skipped.
      class BackfillProposal < Base
        fields :id, :community, :endpoint_id, :status, :fetched, :gaps, :ours, :claimed, :below_floor,
               :swept_since, :expires_at, :decided_by, :decided_at, :created_at, readonly: [:id]
      end

      # One message a backfill sweep would relay. The preview is enough to
      # recognise it when deciding, cut well short of the whole body, and it
      # is deleted with the decision.
      class BackfillProposalItem < Base
        fields :native_id, :author_label, :preview, :sent_at
      end

      # {Client#admin_backfill_proposal}'s answer: one proposal, and the
      # messages it would send if accepted. `items` is empty once
      # `items_pruned` is true, which means the previews are gone because
      # the proposal was settled, not because the sweep found nothing to
      # send; `items_note` says what happened to them.
      class BackfillProposalDetail < Base
        fields :backfill_proposal, :items, :items_pruned, :items_note
        cast :backfill_proposal, ->(v) { BackfillProposal.from_h(v) }
        cast :items, ->(v) { BackfillProposalItem.array(v) }
      end

      # What {Client#admin_approve_backfill_proposal} did. `relaying` false
      # means the decision is recorded but nothing is going out; `errors`
      # says why, present only then.
      class BackfillProposalApproval < Base
        fields :backfill_proposal, :item_count, :relaying, :errors
        cast :backfill_proposal, ->(v) { BackfillProposal.from_h(v) }
      end
    end
  end
end
