# frozen_string_literal: true

module Rubotty
  class Client
    module Models
      # A tenant: the top-level thing every room, channel and person belongs to.
      class Community < Base
        fields :slug, :name, :status, :created_at
      end
    end
  end
end
