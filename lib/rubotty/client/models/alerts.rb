# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One thing a script raised for a community's operators. `mode` is
      # "quiet" (recorded and shown) or "loud" (also messaged the operators
      # directly); `delivered_to` is how many a loud alert actually reached.
      class Alert < Base
        fields :id, :text, :mode, :delivered_to, :room_key, :script, :seen_at, :created_at, readonly: [:id]
      end

      # {Client#alerts}'s answer: the page asked for, plus `unseen`, which
      # counts everything outstanding rather than everything on this page.
      class AlertList < Base
        fields :alerts, :unseen
        cast :alerts, ->(v) { Alert.array(v) }
      end
    end
  end
end
