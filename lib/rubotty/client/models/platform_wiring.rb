# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A connection between a community and a platform. Read-only over the
      # API: there are no write verbs for these yet.
      class PlatformConnection < Base
        fields :id, :adapter, :account, :external_id, :label, readonly: [:id]
      end

      # One IRC network a community bridges into. `sasl_password_env` names
      # the environment variable holding the SASL password; the password
      # itself is never here.
      class IrcNetwork < Base
        fields :name, :host, :port, :tls, :nick, :sasl_user, :sasl_password_env, :channels, :mode
      end

      # One Fluxer instance a community bridges into. `api_key_env` names the
      # environment variable holding the API key, never the key itself.
      # `endpoint_url` is null for the hosted flagship.
      class FluxerInstance < Base
        fields :label, :kind, :endpoint_url, :api_key_env
      end
    end
  end
end
