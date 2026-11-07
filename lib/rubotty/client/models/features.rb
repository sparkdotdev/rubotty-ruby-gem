# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One config key a feature's `config` accepts, as {Client#feature_schemas}
      # lists it. `type` is one of "string", "integer", "float", "boolean",
      # "symbol", "array", "hash", "duration" or "any"; `duration` accepts
      # either a plain number of seconds or a string such as "24 hours".
      class ConfigField < Base
        fields :name, :type, :required, :default, :one_of, :description
      end

      # What `config` accepts for one feature, the same shape the dashboard
      # reads to build its per-feature config form.
      class FeatureSchema < Base
        fields :name, :description, :retention_notice, :config_schema
        cast :config_schema, ->(v) { ConfigField.array(v) }
      end

      # A feature row, either the community-wide default or one room's
      # override. `config` stays a plain Hash: which keys it holds and what
      # they mean belongs to the release a deployment is running, not to
      # this gem, and {Client#feature_schemas} is the authority on them.
      class Feature < Base
        fields :scope, :room_key, :feature, :enabled, :config
      end

      # A room's answer to "what does this feature resolve to here, and
      # where did that come from". Everything {Feature} has, plus
      # `inherited`: false when the room carries an override of its own, in
      # which case `scope` is "room".
      class RoomFeature < Feature
        fields :inherited
      end
    end
  end
end
