# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A platform account, belonging to the deployment rather than to any
      # one community. `settings` stays a plain Hash: it carries the token's
      # environment variable NAME and per-adapter behaviour flags, never a
      # raw secret, and its keys vary by adapter.
      class Account < Base
        fields :id, :adapter, :name, :settings, :source, readonly: [:id]
      end

      # One API key. `public_id` is how it is named in the dashboard and the
      # logs; the token itself is never here.
      class ApiKey < Base
        fields :public_id, :scope, :community, :label, :created_by, :revoked_at, :last_used_at,
               readonly: [:public_id]
      end

      # A deployment-wide connection to an outside service, e.g.
      # LibreTranslate, configured or not. `config` stays a plain Hash: what
      # it holds is specific to the integration named in `name`.
      class Integration < Base
        fields :name, :url, :api_key_set, :config, :updated_at
      end
    end
  end
end
