# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One holder of the community-scoped viewer dimension, who reads this
      # one community and changes nothing in it.
      class CommunityViewer < Base
        fields :id, :community_id, :adapter, :handle, :native_id, :requires_regrant, :label,
               :granted_at, :granted_by, :removable, readonly: %i[id community_id removable]
      end

      # Somebody's ask to read one community, waiting on an operator of it.
      class CommunityViewerRequest < Base
        fields :id, :community_id, :adapter, :requester_username, :requester_display, :state, :requested_at,
               :decided_at, readonly: %i[id community_id]
      end

      # {Client#community_viewers}'s two lists: `viewers` are the granted
      # entries, which {Client#revoke_community_viewer} can remove;
      # `baked_in` are the handles the deployment ships with, which read
      # every community and cannot be revoked anywhere.
      class CommunityViewerRoster < Base
        fields :viewers, :baked_in
        cast :viewers, ->(v) { CommunityViewer.array(v) }
        cast :baked_in, ->(v) { BakedInViewer.array(v) }
      end

      # What deciding a {CommunityViewerRequest} produced: the request as it
      # now stands, and the viewer entry granting it created.
      class CommunityViewerRequestDecision < Base
        fields :request, :viewer
        cast :request, ->(v) { CommunityViewerRequest.from_h(v) }
        cast :viewer, ->(v) { CommunityViewer.from_h(v) }
      end

      # One granted holder of the deployment-wide viewer dimension, who reads
      # every community and changes nothing anywhere.
      class Viewer < Base
        fields :id, :adapter, :handle, :native_id, :requires_regrant, :label, :granted_at,
               :granted_by, :removable, readonly: %i[id removable]
      end

      # A handle the deployment ships with, the floor under the granted
      # entries. Carries no id, because there is nothing to address and
      # nothing to revoke.
      class BakedInViewer < Base
        fields :handle, :kind, :removable, readonly: [:removable]
      end

      # Somebody's ask to read every community, waiting on an administrator.
      class ViewerRequest < Base
        fields :id, :adapter, :requester_username, :requester_display, :state, :requested_at, :decided_at,
               readonly: [:id]
      end

      # {Client#admin_viewers}'s two lists, the deployment-wide equivalent of
      # {CommunityViewerRoster}.
      class ViewerRoster < Base
        fields :viewers, :baked_in
        cast :viewers, ->(v) { Viewer.array(v) }
        cast :baked_in, ->(v) { BakedInViewer.array(v) }
      end

      # What deciding a {ViewerRequest} produced: the request as it now
      # stands, and the viewer entry granting it created.
      class ViewerRequestDecision < Base
        fields :request, :viewer
        cast :request, ->(v) { ViewerRequest.from_h(v) }
        cast :viewer, ->(v) { Viewer.from_h(v) }
      end

      # A token somebody can be handed so they are granted a role by sending
      # it to the bot. The token string is absent here and always will be:
      # only its digest is kept, so nothing can hand it back. See
      # {IssuedAuthToken} for the one moment it is readable.
      class AuthToken < Base
        fields :public_id, :community, :grants, :label, :state, :created_by, :created_at, :expires_at,
               :redeemed_at, :redeemed_by, :revoked_at, readonly: %i[public_id state created_at]
      end

      # What {Client#mint_community_auth_token} and
      # {Client#admin_mint_auth_token} answer with: everything {AuthToken}
      # has, plus the token string itself, shown here and nowhere else ever.
      class IssuedAuthToken < AuthToken
        fields :token, readonly: [:token]
      end
    end
  end
end
