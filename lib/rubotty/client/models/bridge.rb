# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # What {Client#post_bridge_message} got back. `message_id` is what a
      # later edit, delete or reaction on this same channel addresses.
      class BridgeMessageQueued < Base
        fields :status, :message_id
      end

      # What every other bridge write, an edit, a delete or a reaction, gets
      # back: accepted onto the queue, `status` always "queued". No platform
      # has seen it yet.
      class QueuedStatus < Base
        fields :status
      end
    end
  end
end
