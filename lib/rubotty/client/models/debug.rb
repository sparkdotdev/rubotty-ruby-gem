# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # The analytics overview {Client#admin_community_stats} answers with,
      # for the default window. `window`, `since` and `now` are the only
      # fields worth naming here; `sections` holds one sub-object each for
      # moderation, members, messages, reactions, guests, warnings,
      # sanctions, events, multiposts, onboarding and operator requests,
      # deliberately left unmodelled and reached by its own key, since a
      # fixed set of accessors here would describe today's aggregates rather
      # than whichever release a deployment is actually running.
      class Stats < Base
        fields :window, :since, :now
        remainder :sections
      end

      # What the script toolchain on a process's host looks like, and why a
      # language may be missing from it. `dialects` stays a plain Hash,
      # keyed by language name.
      class ScriptingInfo < Base
        fields :interpreter, :searched, :dialects
      end

      # One process's build and runtime facts, from
      # {Client#admin_debug_info}. For a bot source, `reachable` reports
      # whether the internal hop succeeded; when it is false, `error`
      # explains why and the build fields are absent. `stranded_endpoints`
      # stays a plain Hash: endpoint id to a discard count, present only on
      # the bot.
      class ProcessInfo < Base
        fields :version, :commit, :hostname, :runtime, :platform, :pid, :healthy, :reachable, :error,
               :scripting, :stranded_endpoints
        cast :scripting, ->(v) { ScriptingInfo.from_h(v) }
        remainder :extra
      end

      # {Client#admin_debug_info}'s answer. `web` and `bot` are each nil
      # when `source:` did not ask for that process.
      class DebugInfo < Base
        fields :web, :bot
        cast :web, ->(v) { ProcessInfo.from_h(v) }
        cast :bot, ->(v) { ProcessInfo.from_h(v) }
      end

      # One log line. The one place a timestamp is UTC ISO 8601 rather than
      # the wall-clock form used everywhere else in this API.
      class LogEntry < Base
        fields :source, :time, :level, :text
      end

      # {Client#admin_debug_logs}'s answer. `errors` stays a plain Hash,
      # process name to why it could not be read, present only when a
      # requested source failed.
      class DebugLog < Base
        fields :entries, :errors
        cast :entries, ->(v) { LogEntry.array(v) }
      end
    end
  end
end
