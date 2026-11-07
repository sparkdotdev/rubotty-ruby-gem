# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One operator-authored script. The compiled output is never returned,
      # only `source`, exactly as it was written. `trigger_config` stays a
      # plain Hash: which fields it takes depends on `condition`, as
      # {Client#admin_scripting_capabilities} lists them.
      class Script < Base
        fields :id, :name, :kind, :language, :source, :yaml_data, :condition, :trigger_config, :enabled,
               :checked, :archived, :disabled_reason, :community, readonly: %i[id checked archived community]
      end

      # What {Client#admin_verify_script} answered. Answers rather than
      # raises when a script fails, because a script that does not compile
      # is a normal answer to this question: `problems` is an empty list
      # when it passed, and the collected reasons as one string when it did not.
      class ScriptVerification < Base
        fields :ok, :problems, readonly: %i[ok problems]
      end

      # One named outbound address a script may call. Headers are never
      # echoed back, only `has_headers`, since they carry an API key nothing
      # downstream may read.
      class ScriptEndpoint < Base
        fields :id, :name, :url, :http_method, :description, :allow_sync, :enabled, :timeout_seconds,
               :cache_seconds, :query_params, :has_headers, readonly: [:id]
      end

      # One row of a counter a script recorded, under
      # {Client#admin_script_stats}'s counter name.
      class ScriptStatRow < Base
        fields :row, :value, :room_key
      end

      # One kind of script this deployment runs, from
      # {Client#admin_scripting_capabilities}.
      class ScriptKind < Base
        fields :kind, :label
      end

      # One trigger condition a script may be woken by, from
      # {Client#admin_scripting_capabilities}.
      class ScriptCondition < Base
        fields :condition, :summary, :fields, :hands_over
      end

      # What this deployment allows a script to do, enforced on every write
      # and every run.
      class ScriptingLimits < Base
        fields :scripts_per_community, :host_calls_per_invocation, :yaml_data_bytes
      end

      # What a script may be on this deployment: the kinds, the trigger
      # conditions, the languages actually installed here (which transpiler
      # is present on the host decides this, so it differs between
      # deployments) and the limits enforced.
      class ScriptingCapabilities < Base
        fields :kinds, :conditions, :languages, :limits
        cast :kinds, ->(v) { ScriptKind.array(v) }
        cast :conditions, ->(v) { ScriptCondition.array(v) }
        cast :limits, ->(v) { ScriptingLimits.from_h(v) }
      end

      # One failure, truncated at the point it was recorded, since a script
      # can build an error out of text it was handed.
      class ScriptError < Base
        fields :at, :message
      end

      # A script's failure record. Everything is empty or zero for one that
      # has never failed on live traffic, which is the healthy answer rather
      # than a 404.
      class ScriptErrors < Base
        fields :id, :name, :consecutive_failures, :disabled_at, :disabled_reason, :last_error, :last_error_at,
               :errors, readonly: %i[id name]
        cast :errors, ->(v) { ScriptError.array(v) }
      end
    end
  end
end
