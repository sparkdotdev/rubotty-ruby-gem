# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A standing instruction to forward a community's events to an
      # address. The signing secret is returned on creation and on rotation
      # only, never here; see {WebhookWithSecret}.
      class Webhook < Base
        fields :public_id, :url, :label, :event_types, :room_key, :active, :rotating, :created_at,
               readonly: [:public_id]
      end

      # What {Client#admin_create_webhook} and
      # {Client#admin_rotate_webhook_secret} answer with: everything
      # {Webhook} has, plus `secret`, in the Standard Webhooks `whsec_`
      # format. One of only two responses this API ever carries it on.
      class WebhookWithSecret < Webhook
        fields :secret, readonly: [:secret]
      end

      # One event's journey to one subscriber: whether it was delivered,
      # and what the subscriber answered if not.
      class WebhookDelivery < Base
        fields :id, :event_id, :event_type, :room_key, :status, :attempts, :response_status, :last_error,
               :created_at, :delivered_at, readonly: [:id]
      end
    end
  end
end
