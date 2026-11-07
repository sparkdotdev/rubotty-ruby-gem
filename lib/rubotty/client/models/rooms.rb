# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A room. `channels` carries the endpoint_keys of every channel bridged
      # into it, plain strings rather than full {Channel} rows, so knowing
      # what a room spans takes no second call.
      class Room < Base
        fields :room_key, :label, :channels
      end

      # One bridged channel.
      class Channel < Base
        fields :endpoint_key, :adapter, :account, :label, :receives, :sends
      end

      # A channel a non-operator named with the topic command, still waiting
      # on a decision. Everything {Channel} has, plus the id
      # {Client#approve_suggested_channel} and {Client#reject_suggested_channel}
      # address it by.
      class SuggestedChannel < Channel
        fields :id, readonly: [:id]
      end

      # One discovered channel and what applying its mapping would do.
      # `action` is "bind", "create" or "skip"; a skip carries `reason` and no
      # room.
      class MappingProposal < Base
        fields :endpoint_key, :channel_label, :action, :room_key, :room_label, :reason
      end

      # What {Client#map_discovered_channel} produced: the room the channel
      # landed in, and every channel now in it.
      class ChannelMapping < Base
        fields :room, :channels
        cast :room, ->(v) { Room.from_h(v) }
        cast :channels, ->(v) { Channel.array(v) }
      end

      # What {Client#apply_mapping_proposals} did. Compare `applied` against
      # `requested` to see whether anything was dropped: a channel that
      # stopped being discovered-and-unmapped between proposing and applying
      # is skipped rather than acted on.
      class MappingApplyResult < Base
        fields :applied, :requested
      end
    end
  end
end
