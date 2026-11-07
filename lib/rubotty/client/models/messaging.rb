# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # What {Client#post_message} got back: the message was accepted onto
      # the queue, not yet delivered. `status` is always "queued".
      class MessageQueued < Base
        fields :status, :id, :room_key, readonly: [:id]
      end

      # One buffered message inside a {StreamFrame}. There is no per-platform
      # id here, since the buffer records what the room saw rather than each
      # platform's own copy of it.
      class StreamMessage < Base
        fields :id, :origin, :author, :body, :kind, :at, readonly: [:id]
      end

      # One frame of {Client#stream_room}'s server-sent event feed. The
      # opening frame carries an empty `messages` and the cursor the stream
      # starts from, so a subscriber confirms the stream is live and pins its
      # cursor even on a silent room.
      class StreamFrame < Base
        fields :room_key, :cursor, :messages
        cast :messages, ->(v) { StreamMessage.array(v) }
      end
    end
  end
end
