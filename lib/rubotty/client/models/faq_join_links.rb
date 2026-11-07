# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # One FAQ entry. Exactly one of `command` or `keyword` is present,
      # matching how it was added: `trigger_type: "command"` at
      # {Client#add_faq_entry} fills `command`, anything else fills `keyword`.
      class FaqEntry < Base
        fields :id, :command, :keyword, :response, readonly: [:id]
      end

      # One public join link.
      class JoinLink < Base
        fields :platform, :label, :url
      end
    end
  end
end
