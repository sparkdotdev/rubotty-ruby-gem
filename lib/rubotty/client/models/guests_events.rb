# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A guest invite. Never carries a token: only its digest is stored, and
      # the raw token is shown to the inviter once, at issuance, so it never
      # appears in a response this gem decodes.
      class GuestInvite < Base
        fields :id, :nickname, :room_key, :created_by, :expires_at, :revoked_at, :joined_at, readonly: [:id]
      end

      # One scheduled event. `kind` decides which of `game_title` and
      # `server_address` apply; both are null on a "general" event.
      class Event < Base
        fields :id, :room_key, :title, :description, :starts_at, :ends_at, :timezone, :kind, :game_title,
               :server_address, :url, :rsvp_mode, readonly: [:id]
      end
    end
  end
end
