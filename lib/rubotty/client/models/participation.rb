# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # The one open session in a room, exactly as a script's own session()
      # call sees it. Rubotty holds no list of what a session may be called,
      # so `kind` is whatever the script that opened it chose.
      class ParticipationSession < Base
        fields :kind, :label, :state, :opened_at, :rounds, :participants
      end

      # One person's place on a session's leaderboard.
      class ParticipationStanding < Base
        fields :who, :score, :answered
      end

      # {Client#room_participation}'s answer. `session` is nil when nothing
      # is running in the room; `standings` is always an array, empty when
      # there is no session or nobody has answered yet.
      class RoomParticipation < Base
        fields :session, :standings
        cast :session, ->(v) { ParticipationSession.from_h(v) }
        cast :standings, ->(v) { ParticipationStanding.array(v) }
      end
    end
  end
end
