# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One platform account observed to be a given {Person}.
      class PersonIdentity < Base
        fields :adapter, :native_id, :username
      end

      # A passively observed identity: a row appears by observing someone
      # talk, never by an explicit create. `nicknames` stays a plain Hash,
      # keyed by whichever platform each name is shown on, since the set of
      # platforms is open-ended rather than a fixed shape worth its own class.
      class Person < Base
        fields :id, :name, :identities, :nicknames, readonly: [:id]
        cast :identities, ->(v) { PersonIdentity.array(v) }
      end

      # One person's granted authority to moderate a community, as a record
      # {Client#admin_revoke_operator} can address. `baked_in` is always
      # false here; a handle the deployment ships with as an owner comes back
      # as {BakedInOperator} instead.
      class Operator < Base
        fields :id, :person, :actions, :scope, :granted_at, :granted_by, :baked_in, :removable,
               readonly: %i[id baked_in removable]
      end

      # A handle the deployment ships with as an owner, in every community by
      # virtue of the handle alone. Carries no id and no grant record: there
      # is nothing to address and nothing to revoke, which is what
      # `removable` being always false says plainly.
      class BakedInOperator < Base
        fields :handle, :kind, :actions, :scope, :baked_in, :removable, readonly: %i[baked_in removable]
      end

      # A request for operator authority over one community, whatever its
      # state, pending and decided alike.
      class OperatorRequest < Base
        fields :id, :adapter, :requester_username, :requester_display, :state, :requested_at, :decided_at,
               readonly: [:id]
      end
    end
  end
end
